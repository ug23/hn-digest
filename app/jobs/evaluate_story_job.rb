# llm キューで動かす。config/queue.yml で llm の worker を 1 スレッドにしてあり、ollama への依頼が直列になる。
class EvaluateStoryJob < ApplicationJob
  queue_as :llm
  retry_on Ollama::Error, wait: 10.minutes, attempts: 3

  # qwen3-embedding は検索する側（クエリ）に指示文を付けると精度が上がる
  QUERY_PREFIX = "Instruct: Given a reader's interest profile, retrieve articles the reader would find worth reading\nQuery: ".freeze

  def perform(story, profile = Profile.current)
    return if Evaluation.exists?(story: story, profile: profile)

    if (note = profile.exclusion_note(story))
      return Evaluation.create!(story: story, profile: profile, status: "excluded", note: note)
    end

    story.update!(embedding_vector: Ollama.embed([ story.embed_text ]).first) unless story.embedding
    profile.update!(embedding_vector: Ollama.embed([ QUERY_PREFIX + profile.description ]).first) unless profile.embedding

    similarity = Embeddable.cosine(story.embedding_vector, profile.embedding_vector)
    cutoff = profile.similarity_cutoff
    if cutoff && similarity < cutoff
      return Evaluation.create!(story: story, profile: profile, status: "filtered", similarity: similarity)
    end

    result = Scorer.call(story, profile)
    Evaluation.create!(
      story: story, profile: profile, status: "scored", similarity: similarity, model: Ollama::CHAT_MODEL,
      score: profile.adjusted_score(result[:llm_score], result[:tags]), **result
    )
  rescue ActiveRecord::RecordNotUnique
    # 同じ組を別のジョブが先に保存した。評価は1組に1行なので何もしなくてよい
  end
end
