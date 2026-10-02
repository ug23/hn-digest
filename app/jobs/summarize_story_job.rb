# llm キュー(1スレッド)で動かし、ollama への依頼を直列にする。
class SummarizeStoryJob < ApplicationJob
  queue_as :llm
  retry_on Ollama::Error, wait: 10.minutes, attempts: 3

  COMMENT_CHARS = 15_000

  SCHEMA = {
    type: "object",
    properties: {
      key_points: { type: "array", items: { type: "string" }, minItems: 3, maxItems: 3 },
      relevance: { type: "string" }, discussion: { type: "string" }, verdict: { type: "string" }
    },
    required: %w[key_points relevance discussion verdict]
  }.freeze

  def perform(story)
    return if Summary.exists?(story: story)

    profile = Profile.current
    system, user = Prompt.render("summarize", story: story, profile: profile, comments: comments_text(story))
    hash = Ollama.chat_json(system: system, user: user, schema: SCHEMA, num_predict: 1500) { |h| Summary.valid_result?(h) }
    Summary.create!(story: story, model: Ollama::CHAT_MODEL, **hash.slice("key_points", *Summary::TEXT_KEYS).symbolize_keys)

    # should_read が yes の記事は、要約の直後に自動で訳す(Design Doc U14)
    if story.body_text && Evaluation.exists?(story: story, profile: profile, should_read: "yes") && !Translation.exists?(story: story)
      TranslateStoryJob.perform_later(story)
    end
  rescue ActiveRecord::RecordNotUnique
    # 同じ記事を別のジョブが先に要約した。要約は1記事に1行なので何もしなくてよい
  end

  private

  # コメントの合計を打ち切る。本文と合わせて num_ctx(16384)を超えると、ollama が先頭の system を切り捨てるため
  def comments_text(story)
    text = story.comments.each_with_index.map do |c, i|
      [ "#{i + 1}. #{c["text"]}", *c["replies"].to_a.map { |r| "   - 返信: #{r}" } ].join("\n")
    end.join("\n")
    text.empty? ? "(コメントなし)" : text[0, COMMENT_CHARS]
  end
end
