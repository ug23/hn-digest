require "net/http"

# ollama の REST API（http://localhost:11434）の呼び出し。外部の LLM / 埋め込み API は使わない。
module Ollama
  class Error < StandardError; end
  class InvalidResponse < Error; end

  # 接続先とモデルは環境変数で差し替えられる。既定値は開発時に使っていた構成である。
  # 埋め込みモデルを変えると、保存済みのベクトルと次元や意味が合わなくなる(記事とプロファイルの埋め込みを作り直す)
  BASE_URL = ENV.fetch("OLLAMA_HOST", "http://localhost:11434").freeze
  EMBED_MODEL = ENV.fetch("OLLAMA_EMBED_MODEL", "qwen3-embedding:4b").freeze
  CHAT_MODEL = ENV.fetch("OLLAMA_CHAT_MODEL", "qwen3.8:27b-mlx").freeze

  module_function

  def embed(texts, model: EMBED_MODEL)
    # keep_alive: 0 で使い終わったら即アンロードさせる。18GB の chat モデルと同時に載ると
    # Metal の Insufficient Memory で落ちることがあったため、埋め込みモデルは呼び出しの間だけ載せる
    post("/api/embed", { model: model, input: texts, keep_alive: 0 }, read_timeout: 180).fetch("embeddings")
  end

  # JSON を返させて parse し、ブロックで妥当性を確かめる。parse 失敗か検証落ちなら1回だけ再試行する。
  #
  # 注意: MLX 版のモデルは format（JSON Schema）の制約が効かない、あるいはハングすることがある
  # （Design Doc 3.1節の実測）。format に頼らず、呼び出し側が system プロンプトに出力キーと型を書くこと。
  # さらに num_predict・読み取りタイムアウト・ここでの検証で守る。
  # think: false、num_ctx、temperature は既定のモデル(qwen3.8)向けの調整で、別のモデルでは効き方が違いうる
  def chat_json(system:, user:, schema:, model: CHAT_MODEL, num_predict: 800)
    attempts = 0
    begin
      attempts += 1
      body = {
        model: model, stream: false, format: schema, think: false,
        messages: [ { role: "system", content: system }, { role: "user", content: user } ],
        options: { temperature: 0, num_ctx: 16384, num_predict: num_predict }
      }
      content = post("/api/chat", body, read_timeout: 180).dig("message", "content").to_s
      hash = JSON.parse(content[/\{.*\}/m] || content) # 前後に余計な文字があっても最初の { から最後の } までを取る
      raise InvalidResponse, "応答が検証を通らない: #{content[0, 200]}" unless hash.is_a?(Hash) && (!block_given? || yield(hash))

      hash
    rescue JSON::ParserError, InvalidResponse => e
      retry if attempts < 2 # 接続失敗やタイムアウトは再試行しない（ジョブの retry_on に任せる）
      raise e.is_a?(Error) ? e : Error.new("JSON として解釈できない: #{e.message}")
    end
  end

  def post(path, payload, read_timeout:)
    uri = URI("#{BASE_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = read_timeout
    response = http.post(uri.path, payload.to_json, "Content-Type" => "application/json")
    raise Error, "ollama HTTP #{response.code}: #{response.body.to_s[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue Error
    raise
  rescue StandardError => e # 接続拒否、タイムアウト、応答 JSON の parse 失敗など
    raise Error, "ollama の呼び出しに失敗: #{e.class}: #{e.message}"
  end
end
