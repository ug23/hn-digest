# llm キューで動かす。config/queue.yml で llm の worker を 1 スレッドにしてあり、ollama への依頼が直列になる。
class EvaluateStoryJob < ApplicationJob
  queue_as :llm
  retry_on Ollama::Error, wait: 10.minutes, attempts: 3

  # qwen3-embedding は検索する側（クエリ）に指示文を付けると精度が上がる。別の埋め込みモデルでは不要か、別の形式になりうる
  QUERY_PREFIX = "Instruct: Given a reader's interest profile, retrieve articles the reader would find worth reading\nQuery: ".freeze

  # cutoff は一次フィルタの基準値。RescoreJob は全記事で同じ値を使うため、引数で受け取れるようにしてある（nil は「絞らない」）
  # broadcast: true は RescoreJob から積まれたときだけ。再採点の表の行を差し替える。通常の毎時の評価では描画も配信もしない
  def perform(story, profile = Profile.current, cutoff = profile.similarity_cutoff, broadcast: false)
    return if Evaluation.exists?(story: story, profile: profile)

    evaluation = evaluate(story, profile, cutoff)
    SummarizeStoryJob.perform_later(story) if evaluation.above_threshold?
    broadcast_rescore_row(story, profile, evaluation) if broadcast # 失敗しても、評価と要約の投入は済んでいる
  rescue ActiveRecord::RecordNotUnique
    # 同じ組を別のジョブが先に保存した。評価は1組に1行なので何もしなくてよい
  end

  private

  def evaluate(story, profile, cutoff)
    if (note = profile.exclusion_note(story))
      return Evaluation.create!(story: story, profile: profile, status: "excluded", note: note)
    end

    story.update!(embedding_vector: Ollama.embed([ story.embed_text ]).first) unless story.embedding
    profile.update!(embedding_vector: Ollama.embed([ QUERY_PREFIX + profile.description ]).first) unless profile.embedding

    similarity = Embeddable.cosine(story.embedding_vector, profile.embedding_vector)
    if cutoff && similarity < cutoff
      return Evaluation.create!(story: story, profile: profile, status: "filtered", similarity: similarity)
    end

    result = Scorer.call(story, profile)
    Evaluation.create!(
      story: story, profile: profile, status: "scored", similarity: similarity, model: Ollama::CHAT_MODEL,
      score: profile.adjusted_score(result[:llm_score], result[:tags]), **result
    )
  end

  # プロファイル編集画面の再採点の表で、この記事の行を「旧 → 新」に差し替える。
  # 購読者がいなくてもメッセージは Solid Cable の DB に書かれ、保持期間のあいだ残る
  def broadcast_rescore_row(story, profile, evaluation)
    old = profile.previous&.then { |prev| Evaluation.find_by(story: story, profile: prev) }
    Turbo::StreamsChannel.broadcast_replace_to(
      profile, :rescore, target: ActionView::RecordIdentifier.dom_id(story, :rescore),
      partial: "profiles/rescore_row", locals: { story: story, old: old, new: evaluation }
    )
  end
end
