class FetchStoryJob < ApplicationJob
  queue_as :default

  RETRY_DELAYS = [ 1.hour, 4.hours ].freeze # 3回目の失敗で諦める

  def perform(story)
    return unless story.content_status == "pending"

    begin
      # コメントは本文の成否に関係なく保存する（タイトルだけの採点は甘くなるため）
      story.comments = Hn.top_comments(story.hn_id)
      if story.url.blank?
        story.assign_attributes(content: story.story_text, content_status: "fetched")
      else
        story.assign_attributes(content: ContentFetcher.fetch(story.url), content_status: "fetched", fetch_error: nil)
      end
    rescue StandardError => e
      # コメント取得の失敗も本文の失敗と同じく試行回数に数え、pending のまま無期限に再投入されないようにする
      record_failure(story, e)
    end
    story.save!
    EvaluateStoryJob.perform_later(story) unless story.content_status == "pending"
  end

  private

  def record_failure(story, error)
    story.fetch_attempts += 1
    story.fetch_error = "#{error.class}: #{error.message}".truncate(255)
    if (delay = RETRY_DELAYS[story.fetch_attempts - 1])
      story.retry_after = delay.from_now
    else
      story.content_status = "failed"
    end
  end
end
