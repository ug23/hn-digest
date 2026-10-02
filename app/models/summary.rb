class Summary < ApplicationRecord
  belongs_to :story

  TEXT_KEYS = %w[relevance discussion verdict].freeze

  # LLM の応答の検証。key_points は文字列ちょうど3件、他の3項目は空でない文字列
  def self.valid_result?(hash)
    points = hash["key_points"]
    points.is_a?(Array) && points.size == 3 && points.all? { |p| p.is_a?(String) && p.present? } &&
      TEXT_KEYS.all? { |k| hash[k].is_a?(String) && hash[k].present? }
  end
end
