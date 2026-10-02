require "test_helper"

class FetchStoryJobTest < ActiveJob::TestCase
  # minitest 6 には stub が無いので、Hn.top_comments を一時的に差し替える
  def with_comments(impl)
    original = Hn.method(:top_comments)
    Hn.define_singleton_method(:top_comments, &impl)
    yield
  ensure
    Hn.define_singleton_method(:top_comments, original)
  end

  test "不正な URL は試行回数を数え、retry_after を入れる" do
    story = build_story(url: "http://exa mple.com/x y")
    with_comments(->(*) { [] }) do
      FetchStoryJob.perform_now(story)
    end
    story.reload
    assert_equal 1, story.fetch_attempts
    assert_equal "pending", story.content_status
    assert_in_delta 1.hour.from_now, story.retry_after, 5
  end

  test "コメント取得の失敗も試行に数え、3回目で failed にして評価へ進む" do
    story = build_story
    with_comments(->(*) { raise "boom" }) do
      3.times { FetchStoryJob.perform_now(story.reload) }
    end
    assert_equal "failed", story.reload.content_status
    assert_enqueued_with(job: EvaluateStoryJob)
  end
end
