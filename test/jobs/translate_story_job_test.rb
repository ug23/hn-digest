require "test_helper"

class TranslateStoryJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  def with_codex(impl)
    original = Codex.method(:run)
    Codex.define_singleton_method(:run, &impl)
    yield
  ensure
    Codex.define_singleton_method(:run, original)
  end

  test "chunks は段落を6,000文字以内に束ねる" do
    text = [ "a" * 3000, "b" * 2000, "c" * 2000, "d" * 100 ].join("\n\n")
    chunks = TranslateStoryJob.chunks(text)
    assert_equal [ "a" * 3000 + "\n\n" + "b" * 2000, "c" * 2000 + "\n\n" + "d" * 100 ], chunks
  end

  test "chunks は空白だけの行も段落の区切りとする" do
    assert_equal [ "x\n\ny\n\nw" ], TranslateStoryJob.chunks("x\n \ny\n\n\nw")
    assert_equal [], TranslateStoryJob.chunks("  \n\n ")
  end

  test "chunks は上限を超える段落を、改行、文末、文字数の順で切る" do
    lines = ([ "a" * 3000 ] * 3).join("\n") # 空行の無い9,000文字。改行で切り、束ねると上限を超える分は別のまとまり
    assert_equal [ 3000, 3000, 3000 ], TranslateStoryJob.chunks(lines).map(&:size)

    sentences = ([ "b" * 2500 + "." ] * 3).join(" ") # 改行なし。文末で切る
    assert_equal [ 5003, 2501 ], TranslateStoryJob.chunks(sentences).map(&:size)
    assert_equal [ 2001, 2001 ], TranslateStoryJob.chunks("あ" * 2000 + "。" + "あ" * 2000 + "。", 2500).map(&:size)

    solid = "c" * 13_000 # 切れ目が無ければ文字数
    assert_equal [ 6000, 6000, 1000 ], TranslateStoryJob.chunks(solid).map(&:size)
  end

  test "成功すると segments を順に保存して done にする" do
    story = build_story(content: [ "a" * 4000, "b" * 4000 ].join("\n\n"))
    with_codex(->(prompt, **) { "訳:#{prompt[/<source>\n(.)/, 1]}" }) do
      stream = Turbo::StreamsChannel.send(:stream_name_from, [ story, :translation ]) # private なので send
      assert_broadcasts(stream, 3) do # 2まとまり + 状態表示
        TranslateStoryJob.perform_now(story)
      end
    end
    translation = story.translation.reload
    assert_equal "done", translation.status
    assert_equal [ "訳:a", "訳:b" ], translation.segments.map { |s| s["ja"] }
    assert_equal "a" * 4000, translation.segments.first["source"]
  end

  test "Codex::Error なら failed にして理由を残し、途中までの segments は残す" do
    story = build_story(content: [ "a" * 4000, "b" * 4000 ].join("\n\n"))
    calls = 0
    with_codex(->(*, **) { (calls += 1) == 1 ? "訳1" : raise(Codex::Error, "枠の上限") }) do
      assert_nothing_raised { TranslateStoryJob.perform_now(story) }
    end
    translation = story.translation.reload
    assert_equal "failed", translation.status
    assert_equal "枠の上限", translation.error
    assert_equal [ "訳1" ], translation.segments.map { |s| s["ja"] }
  end

  test "Codex::Error 以外の例外でも failed にして理由を残す" do
    story = build_story(content: "hello")
    with_codex(->(*, **) { raise "予期しない" }) { TranslateStoryJob.perform_now(story) }
    assert_equal [ "failed", "RuntimeError: 予期しない" ], story.translation.reload.then { |t| [ t.status, t.error ] }
  end

  test "本文が無ければ translation を作らない" do
    story = build_story(content: nil)
    with_codex(->(*, **) { raise "呼ばれない" }) { TranslateStoryJob.perform_now(story) }
    assert_nil story.translation
  end

  test "failed からの再実行は segments を空にして始め、done なら何もしない" do
    story = build_story(content: "hello")
    Translation.create!(story: story, status: "failed", segments: [ { "source" => "x", "ja" => "y" } ], error: "e")
    with_codex(->(*, **) { "こんにちは" }) { TranslateStoryJob.perform_now(story) }
    assert_equal [ "こんにちは" ], story.translation.reload.segments.map { |s| s["ja"] }
    assert_nil story.translation.error

    with_codex(->(*, **) { raise "呼ばれない" }) { TranslateStoryJob.perform_now(story) }
    assert_equal "done", story.translation.reload.status
  end
end
