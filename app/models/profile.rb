# 関心プロファイルの版。行は作成後に書き換えず、version が最大の行を現行版とする。
# 例外として embedding だけは、初回の評価時に遅延して埋める。
class Profile < ApplicationRecord
  include Embeddable

  has_many :evaluations, dependent: :destroy

  # 類似度の基準値を出すのに必要な最低件数。これに満たない間は全件を通す
  MIN_SAMPLES = 30

  def self.current
    order(:version).last
  end

  # ハードルールに当たればその説明を、当たらなければ nil を返す
  def exclusion_note(story)
    domain = story.domain
    if (hit = excluded_domains.find { |d| domain == d || domain.end_with?(".#{d}") })
      "除外ドメイン: #{hit}"
    elsif (hit = excluded_keywords.find { |k| story.title.downcase.include?(k.downcase) })
      "除外キーワード: #{hit}"
    end
  end

  # 直近7日の類似度の中央値。件数が足りなければ nil（= 絞らない）
  def similarity_cutoff
    values = evaluations.where.not(similarity: nil).where(created_at: 7.days.ago..).order(:similarity).pluck(:similarity)
    return if values.size < MIN_SAMPLES

    mid = values.size / 2
    values.size.odd? ? values[mid] : (values[mid - 1] + values[mid]) / 2.0
  end

  # 語彙に一致するタグの重みの合計を ±2 に丸めて足し、1〜10 に収める
  def adjusted_score(llm_score, tags)
    delta = tags.sum { |t| tag_weights[t].to_i }.clamp(-2, 2)
    (llm_score + delta).clamp(1, 10)
  end
end
