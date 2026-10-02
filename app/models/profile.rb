# 関心プロファイルの版。行は作成後に書き換えず、version が最大の行を現行版とする。
# 例外として embedding だけは、初回の評価時に遅延して埋める。
class Profile < ApplicationRecord
  include Embeddable

  has_many :evaluations, dependent: :destroy

  # 類似度の基準値を出すのに必要な最低件数。これに満たない間は全件を通す
  MIN_SAMPLES = 30

  validates :description, presence: true
  validates :score_threshold, numericality: { only_integer: true, in: 1..10 }

  def self.current
    order(:version).last
  end

  def previous
    Profile.find_by(version: version - 1)
  end

  # 編集フォームの入力から「現行版 +1」の新しい版を作る(保存はしない)。重みの行が不正なら ArgumentError
  def self.next_from_form(form)
    new(
      version: (maximum(:version) || 0) + 1, description: form[:description].to_s.strip,
      tag_weights: parse_weights(form[:tag_weights]), score_threshold: form[:score_threshold],
      excluded_domains: parse_lines(form[:excluded_domains]), excluded_keywords: parse_lines(form[:excluded_keywords])
    )
  end

  def self.parse_lines(text)
    text.to_s.lines.map(&:strip).reject(&:empty?)
  end

  # 編集フォームに出す値(next_from_form の逆)
  def form_values
    {
      description: description, score_threshold: score_threshold,
      tag_weights: tag_weights.map { |tag, weight| "#{tag}: #{weight}" }.join("\n"),
      excluded_domains: excluded_domains.join("\n"), excluded_keywords: excluded_keywords.join("\n")
    }
  end

  # 1行1件の「タグ: 重み」を {"tag" => 重み} にする。重みは整数だけ
  def self.parse_weights(text)
    parse_lines(text).to_h do |line|
      tag, weight = line.split(/[:：]/, 2).map(&:strip)
      raise ArgumentError, "重みの行が「タグ: 整数」の形ではありません: #{line}" unless tag.present? && weight.to_s.match?(/\A[+-]?\d+\z/)

      [ tag, weight.to_i ]
    end
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

  # 直近7日の類似度の中央値
  def similarity_cutoff
    Profile.cutoff_for(evaluations.where.not(similarity: nil).where(created_at: 7.days.ago..).pluck(:similarity))
  end

  # 類似度の中央値。件数が足りなければ nil（= 絞らない）。RescoreJob も同じ計算を使う
  def self.cutoff_for(similarities)
    return if similarities.size < MIN_SAMPLES

    sorted = similarities.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  # 語彙に一致するタグの重みの合計を ±2 に丸めて足し、1〜10 に収める
  def adjusted_score(llm_score, tags)
    delta = tags.sum { |t| tag_weights[t].to_i }.clamp(-2, 2)
    (llm_score + delta).clamp(1, 10)
  end
end
