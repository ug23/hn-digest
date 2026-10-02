require "net/http"

# Algolia の検索 API と HN 公式 API の呼び出し。
# lib/ 配下は Rails 8 の config.autoload_lib で Zeitwerk が自動で読み込む（手動の require は不要）。
module Hn
  ALGOLIA = "https://hn.algolia.com/api/v1"
  FIREBASE = "https://hacker-news.firebaseio.com/v0"

  module_function

  def search_stories(min_points: 30, since: 48.hours.ago)
    # ">" を生で送ると 400 になるので、必ず URI.encode_www_form でエンコードする
    query = URI.encode_www_form(
      tags: "story",
      numericFilters: "points>=#{min_points},created_at_i>#{since.to_i}",
      hitsPerPage: 1000
    )
    get_json("#{ALGOLIA}/search_by_date?#{query}").fetch("hits")
  end

  # Algolia の hit から stories の属性へ。Ask HN などは url キーが無い
  def story_attributes(hit)
    {
      hn_id: hit["objectID"].to_i,
      title: hit["title"],
      url: hit["url"].presence,
      author: hit["author"],
      points: hit["points"].to_i,
      num_comments: hit["num_comments"].to_i,
      posted_at: Time.at(hit["created_at_i"]).utc,
      story_text: hit["story_text"].presence && plain_text(hit["story_text"])
    }
  end

  # 順位は公式 API の kids（表示順）、本文は Algolia の items から取る。
  # Algolia の items は作成順で points も無く、これだけでは上位を選べないため。
  def top_comments(hn_id, limit: 20, replies: 2)
    kids = get_json("#{FIREBASE}/item/#{hn_id}.json")&.fetch("kids", nil) || [] # 削除済みの記事は null が返る
    nodes = get_json("#{ALGOLIA}/items/#{hn_id}")["children"].to_a.index_by { |c| c["id"] }
    kids.filter_map do |id|
      node = nodes[id]
      text = node && plain_text(node["text"])
      next if text.blank?

      replied = node["children"].to_a.filter_map { |r| plain_text(r["text"])[0, 500].presence }.first(replies)
      { "author" => node["author"], "text" => text[0, 1000], "replies" => replied }
    end.first(limit)
  end

  # HTML をプレーンテキストにする。p タグは空行、br は改行にして段落を残す
  def plain_text(html)
    return "" if html.blank?

    Nokogiri::HTML.fragment(html.gsub(/<p>/i, "\n\n").gsub(/<br\s*\/?>/i, "\n")).text.strip
  end

  def get_json(url)
    response = Net::HTTP.get_response(URI(url))
    raise "HTTP #{response.code}: #{url}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
