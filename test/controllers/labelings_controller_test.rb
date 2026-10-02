require "test_helper"

class LabelingsControllerTest < ActionDispatch::IntegrationTest
  test "直近7日の評価で未評価の記事だけを、評価の新しい順に出す" do
    profile = build_profile
    other = build_profile # 現行版
    old_profile_story = build_story(title: "旧版だけ")
    Evaluation.create!(story: old_profile_story, profile: profile, status: "scored", llm_score: 5, score: 5, should_read: "no")

    newer = build_story(title: "新しい記事")
    older = build_story(title: "古い記事")
    filtered = build_story(title: "落ちた記事")
    rated = build_story(title: "評価済み")
    stale = build_story(title: "8日前")
    Evaluation.create!(story: older, profile: other, status: "scored", llm_score: 5, score: 5, should_read: "skim", reasons: [ "採点の理由" ], created_at: 2.days.ago)
    Evaluation.create!(story: newer, profile: other, status: "scored", llm_score: 8, score: 8, should_read: "yes", created_at: 1.day.ago)
    Evaluation.create!(story: filtered, profile: other, status: "filtered", similarity: 0.1, created_at: 3.days.ago)
    Evaluation.create!(story: rated, profile: other, status: "scored", llm_score: 5, score: 5, should_read: "no")
    Evaluation.create!(story: stale, profile: other, status: "scored", llm_score: 5, score: 5, should_read: "no", created_at: 8.days.ago)
    Feedback.create!(story: rated, rating: 1)
    Summary.create!(story: newer, key_points: %w[要点A 要点B 要点C], relevance: "r", discussion: "論点です", verdict: "v")

    get labeling_path
    assert_response :success
    assert_select "[data-controller='labeling']"
    assert_equal [ "新しい記事", "古い記事", "落ちた記事" ], css_select("article.card a.title").map(&:text)
    assert_select "article.card li", text: "要点A"
    assert_select "article.card li", text: "採点の理由"
    assert_select "article.card button[data-rating]", 6
  end

  test "対象が無ければ空の案内を出す" do
    build_profile
    get labeling_path
    assert_response :success
    assert_select "[data-controller='labeling']", count: 0
  end
end
