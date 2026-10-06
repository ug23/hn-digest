require "test_helper"

class StoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @profile = build_profile
    @story = build_story(content: "本文です")
    Evaluation.create!(story: @story, profile: @profile, status: "scored", llm_score: 6, score: 7,
                       reasons: [ "理由" ], tags: [ "backend" ], should_read: "yes")
  end

  test "http/https の URL はそのままリンクにし、それ以外は HN の記事ページに倒す" do
    get story_path(@story)
    assert_select "h1 a[href='#{@story.url}']"

    @story.update!(url: "javascript:alert(1)")
    get story_path(@story)
    assert_select "a[href^='javascript']", count: 0
    assert_select "h1 a[href='#{@story.hn_url}']"
  end

  test "要約が無ければ要約の節を出さず、翻訳ボタンを出す" do
    get story_path(@story)
    assert_response :success
    assert_select "dl.summary", count: 0
    assert_select "form[action='#{story_translation_path(@story)}'] button", text: "翻訳する"
    assert_select "div.tags span", text: "backend"
  end

  test "要約があれば4項目を出す" do
    Summary.create!(story: @story, key_points: %w[要点A 要点B 要点C], relevance: "接点X", discussion: "論点Y", verdict: "精読Z")
    get story_path(@story)
    assert_select ".key-points li", 3
    assert_select "dl.summary dd", text: "接点X"
    assert_select "dl.summary dd", text: "論点Y"
    assert_select "dl.summary dd", text: "精読Z"
  end

  test "翻訳 running は進行中を出し、ボタンを出さない" do
    Translation.create!(story: @story, status: "running")
    get story_path(@story)
    assert_match "翻訳中", response.body
    assert_select "#translation_status button", count: 0
  end

  test "止まった running(15分以上動きが無い)は再実行ボタンを出す" do
    Translation.create!(story: @story, status: "running", updated_at: 20.minutes.ago)
    get story_path(@story)
    assert_select "#translation_status button", text: "もう一度翻訳する"
  end

  test "翻訳 done はまとまりごとに訳と折りたたんだ原文を出す" do
    Translation.create!(story: @story, status: "done", segments: [ { "source" => "Hello", "ja" => "こんにちは" }, { "source" => "Bye", "ja" => "さようなら" } ])
    get story_path(@story)
    assert_select "#translation_segments .segment", 2
    assert_select ".segment .ja", text: "こんにちは"
    assert_select ".segment details .source", text: "Hello"
    assert_select "#translation_status button", count: 0
  end

  test "翻訳 failed は理由と再実行ボタンを出す" do
    Translation.create!(story: @story, status: "failed", error: "codex が失敗")
    get story_path(@story)
    assert_match "codex が失敗", response.body
    assert_select "#translation_status button", text: "もう一度翻訳する"
  end

  test "本文が20,000文字ちょうどなら打ち切りを表示する" do
    @story.update!(content: "a" * 20_000)
    get story_path(@story)
    assert_match "20,000文字", response.body
    @story.update!(content: "a" * 100)
    get story_path(@story)
    assert_no_match "20,000文字", response.body
  end

  test "本文が無い記事には翻訳ボタンを出さない" do
    @story.update!(content: nil)
    get story_path(@story)
    assert_select "#translation_status button", count: 0
  end
end
