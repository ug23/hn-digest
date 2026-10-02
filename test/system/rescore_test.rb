require "application_system_test_case"

class RescoreTest < ApplicationSystemTestCase
  test "プロファイルを保存すると、再採点の表の新スコアが再読み込みなしで更新される" do
    old = build_profile(embedding_vector: [ 1.0, 0.0 ])
    story = build_story(content_status: "fetched", posted_at: 1.hour.ago, embedding_vector: [ 1.0, 0.0 ])
    Evaluation.create!(story: story, profile: old, status: "scored", score: 3, llm_score: 3)
    embed = ->(texts, **) { texts.map { [ 1.0, 0.0 ] } }
    scored = ->(*, **) { { llm_score: 9, reasons: [], tags: [], should_read: "yes" } }

    visit edit_profile_path
    page.execute_script("window.sameDocument = true")
    fill_in "関心の説明", with: "新しい関心"
    stub_method(RescoreJob, :perform_later, ->(*) { }) do # 購読が済むまでジョブを止める
      click_button "新しい版として保存"
      assert_selector "tr#rescore_story_#{story.id} td:last-child", text: "待ち"
    end
    assert_selector "turbo-cable-stream-source[connected]", visible: :all

    # 新スコアが閾値以上だと要約ジョブが積まれるので、本物の ollama を呼ばないよう止める
    stub_method(SummarizeStoryJob, :perform_later, ->(*) { }) do
      stub_method(Ollama, :embed, embed) { stub_method(Scorer, :call, scored) { RescoreJob.perform_now(Profile.current) } }
    end
    assert_selector "tr#rescore_story_#{story.id} td:last-child", text: "9"
    assert page.evaluate_script("window.sameDocument")
  end
end
