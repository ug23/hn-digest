require "net/http"
require "resolv"
require "ipaddr"

# 記事の URL から本文のテキストを取る。HTML・PDF・GitHub README に対応する。
module ContentFetcher
  class Error < StandardError; end

  MAX_REDIRECTS = 5
  MAX_BYTES = 5 * 1024 * 1024
  MAX_CHARS = 20_000
  MIN_CHARS = 200
  BLOCK_TAGS = "p, h1, h2, h3, h4, h5, h6, li, pre, blockquote, tr, td, th, br, div".freeze
  USER_AGENT = "Mozilla/5.0 (compatible; HNDigest/1.0; personal use)".freeze
  # 取得を拒否するアドレス帯（ループバック等は IPAddr のメソッドで判定する）。CGNAT は tailnet の 100.x を叩かせないため
  BLOCKED_RANGES = %w[0.0.0.0/8 100.64.0.0/10 ::/128].map { |r| IPAddr.new(r) }.freeze

  module_function

  def fetch(url)
    text =
      if (m = url.match(%r{\Ahttps?://(?:www\.)?github\.com/([^/]+)/([^/?#]+)/?\z}))
        get("https://api.github.com/repos/#{m[1]}/#{m[2]}/readme", "Accept" => "application/vnd.github.raw+json").body.then { |b| utf8(b, nil) }
      else
        extract(get(url))
      end
    text.to_s.strip[0, MAX_CHARS]
  rescue Error
    raise
  rescue StandardError => e # 不正な URL、ネットワーク例外、pdf-reader や readability の解析失敗など
    raise Error, "#{e.class}: #{e.message}"
  end

  def extract(response)
    body = response.body
    type = response["content-type"].to_s
    if type.include?("pdf") || body.start_with?("%PDF")
      # ページの間を空行で区切る。ページ内は元の改行を残し、空行の連続だけを1つにする
      PDF::Reader.new(StringIO.new(body)).pages.first(20)
                 .map { |page| page.text.gsub(/[ \t]{2,}/, " ").gsub(/[ \t]*\n[ \t]*/, "\n").gsub(/\n{3,}/, "\n\n").strip }.reject(&:empty?).join("\n\n")
    else
      # charset はヘッダ、無ければ HTML 冒頭の meta から拾う
      charset = type[/charset=["']?([\w-]+)/i, 1] || body.byteslice(0, 2048).b[/<meta[^>]*charset=["']?([\w-]+)/i, 1]
      html = utf8(body, charset)
      text = paragraphs(Readability::Document.new(html).content)
      raise Error, "本文が短すぎる(#{text.size}文字)" if text.size < MIN_CHARS

      text
    end
  end

  # ブロック要素ごとに1段落とし、段落の間を空行1つで区切る（Phase 2 で段落単位に翻訳するため）。
  # 要素の前後に区切り文字(U+2029)を挟んでからテキスト化し、段落内の空白と改行は半角スペース1つにする
  def paragraphs(html)
    doc = Nokogiri::HTML.fragment(html)
    doc.css(BLOCK_TAGS).each do |node|
      node.add_previous_sibling("\u2029")
      node.add_next_sibling("\u2029")
    end
    doc.text.split("\u2029").map(&:squish).reject(&:empty?).join("\n\n")
  end

  # リダイレクトを手で追う。リダイレクト先も毎回ホストを検査する
  def get(url, headers = {}, redirects = MAX_REDIRECTS)
    uri = URI(url)
    raise Error, "http/https 以外は取得しない: #{url}" unless uri.is_a?(URI::HTTP)

    response = request(uri, headers)
    case response
    when Net::HTTPSuccess then response
    when Net::HTTPRedirection
      raise Error, "リダイレクトが多すぎる" if redirects.zero?

      get(URI.join(uri, response["location"]).to_s, headers, redirects - 1)
    else raise Error, "HTTP #{response.code}"
    end
  end

  def request(uri, headers)
    address = public_address(uri.host)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 20
    http.ipaddr = address # 検査したアドレスに固定して接続し、名前解決のすり替えを防ぐ
    req = Net::HTTP::Get.new(uri, { "User-Agent" => USER_AGENT }.merge(headers))
    http.request(req) do |res|
      # 2xx とリダイレクト以外は本文を読まずに終える（例外で接続も閉じる）
      raise Error, "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)

      body = +""
      res.read_body do |chunk|
        body << chunk
        raise Error, "本文が #{MAX_BYTES} バイトを超える" if body.bytesize > MAX_BYTES
      end
      res.body = body
    end
  end

  # HN に貼られた URL 経由で内部ネットワークを叩かないよう、ループバック等に解決されるホストは拒否する
  def public_address(host)
    addresses = Resolv.getaddresses(host)
    raise Error, "名前解決できない: #{host}" if addresses.empty?
    raise Error, "内部アドレスは取得しない: #{host}" unless addresses.all? { |a| public_ip?(a) }

    addresses.first
  end

  def public_ip?(address)
    ip = IPAddr.new(address).native # ::ffff:127.0.0.1 のような IPv4 射影アドレスを IPv4 に戻してから検査する
    !(ip.loopback? || ip.private? || ip.link_local? || BLOCKED_RANGES.any? { |range| range.include?(ip) })
  end

  def utf8(body, charset)
    encoding = (Encoding.find(charset) if charset) rescue nil
    body.dup.force_encoding(encoding || Encoding::UTF_8).encode("UTF-8", invalid: :replace, undef: :replace)
  end
end
