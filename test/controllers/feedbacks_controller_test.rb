require "test_helper"

class FeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup { @story = build_story }

  test "rating を記録し、押し直すと上書きする" do
    post story_feedback_path(@story), params: { rating: 1 }
    assert_equal 1, @story.reload.feedback.rating
    post story_feedback_path(@story), params: { rating: -1 }
    assert_equal [ -1 ], Feedback.where(story: @story).pluck(:rating)
  end

  test "reason の追記は rating を変えない" do
    post story_feedback_path(@story), params: { rating: 1 }
    post story_feedback_path(@story), params: { reason: "良い事後分析" }
    feedback = @story.reload.feedback
    assert_equal 1, feedback.rating
    assert_equal "良い事後分析", feedback.reason
  end

  test "turbo_stream で評価欄を差し替える" do
    post story_feedback_path(@story), params: { rating: 1 }, as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %(target="feedback_story_#{@story.id}"), response.body
  end

  test "HTML は元のページへ戻す" do
    post story_feedback_path(@story), params: { rating: 1 }, headers: { "HTTP_REFERER" => root_url }
    assert_redirected_to root_url
  end

  test "不正な rating は保存しない" do
    post story_feedback_path(@story), params: { rating: 5 }
    assert_response :unprocessable_entity
    assert_nil @story.reload.feedback
  end
end
