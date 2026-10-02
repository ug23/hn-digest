# 新しいプロファイル版で、直近7日の記事を採点し直す。
# プロファイルの埋め込みで ollama を呼ぶので、default ではなく llm キューで動かす。
class RescoreJob < ApplicationJob
  queue_as :llm
  retry_on Ollama::Error, wait: 10.minutes, attempts: 3

  def perform(profile)
    profile.update!(embedding_vector: Ollama.embed([ EvaluateStoryJob::QUERY_PREFIX + profile.description ]).first) unless profile.embedding

    stories = Story.where(posted_at: 7.days.ago..).where(content_status: %w[fetched failed]).order(posted_at: :desc)
    embedded, unembedded = stories.partition(&:embedding)
    similarity = embedded.to_h { |s| [ s, Embeddable.cosine(s.embedding_vector, profile.embedding_vector) ] }
    cutoff = Profile.cutoff_for(similarity.values)

    # cutoff 未満の記事は LLM を呼ばずに終わるので先に積み、結果を早く画面へ出す。埋め込みが無い記事は後ろ
    below, above = embedded.partition { |s| cutoff && similarity[s] < cutoff }
    (below + above + unembedded).each { |story| EvaluateStoryJob.perform_later(story, profile, cutoff, broadcast: true) }
  end
end
