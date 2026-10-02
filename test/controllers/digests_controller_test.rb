require "test_helper"

class DigestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @profile = build_profile
    @story = build_story
    Evaluation.create!(story: @story, profile: @profile, status: "scored", llm_score: 6, score: 7,
                       reasons: [ "理由" ], tags: [ "backend" ], should_read: "yes")
  end

  test "next とルートと all=1 が 200 を返す" do
    get digest_path("next")
    assert_response :success
    assert_match @story.title, response.body
    get root_path
    assert_response :success
    get digest_path("next", all: 1)
    assert_response :success
    assert_select "a[href*='all=1']", count: 0 # all=1 の表示中は絞り込みに戻るリンクだけ
    get digest_path("next")
    assert_select "a[href*='all=1']"
  end

  test "確定済みの日付を表示できる" do
    @story.update!(digested_on: Date.new(2026, 10, 3))
    get digest_path("2026-10-03")
    assert_response :success
    assert_match @story.title, response.body
  end
end
