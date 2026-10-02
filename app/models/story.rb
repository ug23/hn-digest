class Story < ApplicationRecord
  include Embeddable

  has_many :evaluations, dependent: :destroy
  has_one :feedback, dependent: :destroy
  has_one :summary, dependent: :destroy
  has_one :translation, dependent: :destroy

  # 取得待ちで、再試行の時刻に達している記事
  scope :fetchable, -> { where(content_status: "pending").where("retry_after IS NULL OR retry_after <= ?", Time.current) }

  def domain
    host = url && URI.parse(url).host
    host ? host.delete_prefix("www.") : "news.ycombinator.com"
  rescue URI::InvalidURIError
    "news.ycombinator.com"
  end

  # 翻訳と要約の入力になる本文。取得に失敗した記事では nil
  def body_text
    content.presence || story_text.presence
  end

  def hn_url
    "https://news.ycombinator.com/item?id=#{hn_id}"
  end

  # 埋め込みの入力。タイトルと本文の冒頭だけを使う
  def embed_text
    "#{title}\n\n#{(content.presence || story_text).to_s[0, 1000]}".strip
  end
end
