require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { @profile = build_profile(description: "元の説明", tag_weights: { "a" => 1 }, score_threshold: 5) }

  def params(overrides = {})
    { profile: { description: "新しい説明", tag_weights: "a: 2\nb: -1", excluded_domains: "x.com", excluded_keywords: "", score_threshold: "6" }.merge(overrides) }
  end

  test "edit は現行版の値と版番号を出す" do
    get edit_profile_path
    assert_response :success
    assert_match "第#{@profile.version}版", response.body
    assert_select "textarea[name='profile[tag_weights]']", text: "a: 1"
    assert_select "table.rescore", count: 0 # 前の版が無ければ表を出さない
  end

  test "update は新しい版を作り、RescoreJob を積む" do
    assert_enqueued_with(job: RescoreJob) do
      assert_difference -> { Profile.count }, 1 do
        patch profile_path, params: params
      end
    end
    assert_redirected_to edit_profile_path
    current = Profile.current
    assert_equal @profile.version + 1, current.version
    assert_equal({ "a" => 2, "b" => -1 }, current.tag_weights)
    assert_equal [ "x.com" ], current.excluded_domains
    assert_equal 6, current.score_threshold
    assert_nil current.embedding
    assert_equal "元の説明", @profile.reload.description # 旧版は書き換えない
  end

  test "不正な入力は版を増やさず、ジョブも積まず、入力を残して再表示する" do
    [ { tag_weights: "a: x" }, { score_threshold: "99" }, { description: "" } ].each do |bad|
      assert_no_enqueued_jobs(only: RescoreJob) do
        assert_no_difference -> { Profile.count } do
          patch profile_path, params: params(bad)
        end
      end
      assert_response :unprocessable_entity
      assert_select ".error"
    end
    assert_select "textarea[name='profile[description]']", text: ""
  end

  test "前の版の評価がある記事を再採点の表に出し、閾値をまたいだ行を強調する" do
    story = build_story(title: "またぐ記事", posted_at: 1.day.ago)
    stable = build_story(title: "変わらない記事", posted_at: 2.days.ago)
    pending = build_story(title: "待ちの記事", posted_at: 3.days.ago)
    new_profile = build_profile(score_threshold: 5)
    [ story, stable, pending ].each do |s|
      Evaluation.create!(story: s, profile: @profile, status: "scored", llm_score: 3, score: 3, should_read: "no")
    end
    Evaluation.create!(story: story, profile: new_profile, status: "scored", llm_score: 7, score: 7, should_read: "yes")
    Evaluation.create!(story: stable, profile: new_profile, status: "filtered")

    get edit_profile_path
    assert_select "table.rescore tbody tr", 3
    assert_select "tr#rescore_story_#{story.id}.flip td:nth-child(2)", text: "3"
    assert_select "tr#rescore_story_#{story.id} td:nth-child(3)", text: "7"
    assert_select "tr#rescore_story_#{stable.id}:not(.flip) td:nth-child(3)", text: "filtered"
    assert_select "tr#rescore_story_#{pending.id} td:nth-child(3)", text: "待ち"
  end
end
