# external キューで動かす。ollama を使わないので、llm キューの採点や要約を塞がない。
class TranslateStoryJob < ApplicationJob
  queue_as :external

  CHUNK_SIZE = 6000

  # 本文を空行で段落に分け、CHUNK_SIZE 文字以内になるよう段落を束ねる。
  # 1段落が CHUNK_SIZE を超えるときは、改行、文末、文字数の順で切る(空行の無い本文が1回で送られてタイムアウトしないように)
  def self.chunks(text, limit = CHUNK_SIZE)
    text.to_s.split(/\n[ \t]*\n/).map(&:strip).reject(&:empty?).flat_map { |p| cut(p, limit) }.each_with_object([]) do |paragraph, chunks|
      if chunks.any? && chunks.last.size + 2 + paragraph.size <= limit
        chunks.last << "\n\n" << paragraph
      else
        chunks << paragraph.dup
      end
    end
  end

  def self.cut(text, limit)
    pieces = []
    while text.size > limit
      head = text[0, limit]
      # 上限以内で最後の改行、なければ最後の文末(". " や "。")、なければ上限の位置
      at = head.rindex("\n") || head.rindex(/[.!?](?=\s)|。/) || limit - 1
      pieces << text[0, at + 1].strip
      text = text[(at + 1)..].lstrip
    end
    pieces << text
  end

  def perform(story)
    return if story.body_text.nil?

    translation = Translation.find_or_initialize_by(story: story)
    return if translation.status == "done"

    translation.update!(segments: [], status: "running", error: nil, model: Codex::MODEL)
    begin
      self.class.chunks(story.body_text).each do |source|
        ja = Codex.run(Prompt.render("translate", text: source).first)
        translation.update!(segments: translation.segments + [ { "source" => source, "ja" => ja } ])
        # 記事ページは turbo_stream_from で購読している。まとまりが1つ訳せるたびに、その断片だけを末尾へ差し込む。
        # ページの描画と購読開始の間に差し込まれたまとまりは取りこぼすことがある(再読み込みで直る)
        Turbo::StreamsChannel.broadcast_append_to(story, :translation, target: "translation_segments",
                                                  partial: "translations/segment", locals: { segment: translation.segments.last })
      end
      translation.update!(status: "done")
    rescue StandardError => e
      # 自動では再試行しない。running のまま取り残さないよう、Codex::Error 以外でも failed にして理由を残す
      translation.update!(status: "failed", error: e.is_a?(Codex::Error) ? e.message : "#{e.class}: #{e.message}")
    end
    Turbo::StreamsChannel.broadcast_replace_to(story, :translation, target: "translation_status",
                                               partial: "translations/status", locals: { story: story, translation: translation })
  end
end
