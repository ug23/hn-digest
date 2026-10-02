# app/prompts/ の ERB を描画し、区切り行 "=== user ===" で system と user に分けて返す。
# プロンプトは開発者が直すものなので DB ではなくファイル（git 管理）に置く。
class Prompt
  def self.render(name, **locals)
    text = ERB.new(Rails.root.join("app/prompts/#{name}.md.erb").read, trim_mode: "-").result_with_hash(locals)
    text.split(/^=== user ===\n/, 2).map(&:strip)
  end
end
