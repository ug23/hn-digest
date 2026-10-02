require "application_system_test_case"

class TranslationTest < ApplicationSystemTestCase
  test "翻訳を依頼すると、再読み込みなしで訳文が差し込まれる" do
    story = build_story(content: "Hello world")
    visit story_path(story)
    page.execute_script("window.sameDocument = true") # 再読み込みされると消える

    # 購読が済んでから配信させるため、依頼ではジョブを積まず、後で自分で動かす
    stub_method(TranslateStoryJob, :perform_later, ->(*) { }) do
      click_button "翻訳する"
      assert_text "翻訳中です" # リクエストの処理が終わるまで差し替えを保つ
    end
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    stub_method(Codex, :run, ->(*, **) { "こんにちは世界" }) { TranslateStoryJob.perform_now(story) }

    assert_selector "#translation_segments .ja", text: "こんにちは世界"
    assert_no_text "翻訳中です"
    assert page.evaluate_script("window.sameDocument")
  end
end
