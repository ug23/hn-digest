# 記事1件を LLM で採点する。DB には書かない（ジョブと rake の両方から使うため）。
class Scorer
  SCHEMA = {
    type: "object",
    properties: {
      score: { type: "integer", minimum: 1, maximum: 10 },
      reasons: { type: "array", items: { type: "string" }, maxItems: 2 },
      tags: { type: "array", items: { type: "string" }, maxItems: 5 },
      should_read: { type: "string", enum: %w[yes skim no] }
    },
    required: %w[score reasons tags should_read]
  }.freeze

  def self.call(story, profile, model: Ollama::CHAT_MODEL)
    system, user = Prompt.render("score", story: story, profile: profile)
    hash = Ollama.chat_json(system: system, user: user, schema: SCHEMA, model: model) do |h|
      h["score"].is_a?(Integer) && h["score"].between?(1, 10) && SCHEMA[:properties][:should_read][:enum].include?(h["should_read"])
    end
    {
      llm_score: hash["score"],
      reasons: Array(hash["reasons"]).map(&:to_s).first(2),
      tags: Array(hash["tags"]).map(&:to_s).first(5),
      should_read: hash["should_read"]
    }
  end
end
