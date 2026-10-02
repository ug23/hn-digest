require "test_helper"

class ScorerTest < ActiveSupport::TestCase
  def render_system(story = build_story)
    Prompt.render("score", story: story, profile: build_profile, past_ratings: Scorer.past_ratings(story)).first
  end

  test "理由つきの評価が無ければ「読者の過去の評価」の節を出さない" do
    Feedback.create!(story: build_story, rating: 1) # 理由なしは使わない
    assert_no_match "読者の過去の評価", render_system
  end

  test "理由つきの直近5件ずつを、タイトルと理由で入れる" do
    7.times { |i| Feedback.create!(story: build_story(title: "良い#{i}"), rating: 1, reason: "理由良#{i}", updated_at: i.minutes.ago) }
    Feedback.create!(story: build_story(title: "悪い"), rating: -1, reason: "宣伝")
    system = render_system
    assert_match "読者の過去の評価", system
    assert_match "- 良い0: 理由良0", system
    assert_match "- 良い4: 理由良4", system
    assert_no_match "良い5", system
    assert_match "- 悪い: 宣伝", system
  end

  test "採点対象の記事自身の評価は例に入れない" do
    story = build_story(title: "対象")
    Feedback.create!(story: story, rating: 1, reason: "自分の理由")
    assert_no_match "自分の理由", render_system(story)
  end
end
