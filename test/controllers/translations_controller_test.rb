require "test_helper"

class TranslationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { @story = build_story(content: "本文") }

  test "ジョブを積み、running にして記事ページへ戻す" do
    assert_enqueued_with(job: TranslateStoryJob, args: [ @story ]) do
      post story_translation_path(@story)
    end
    assert_redirected_to story_path(@story)
    assert_equal "running", @story.translation.status
  end

  test "failed からの再実行は積み直し、segments と error を消す" do
    Translation.create!(story: @story, status: "failed", error: "e", segments: [ { "source" => "a", "ja" => "b" } ])
    assert_enqueued_jobs(1, only: TranslateStoryJob) { post story_translation_path(@story) }
    assert_equal [ "running", [], nil ], @story.translation.reload.then { |t| [ t.status, t.segments, t.error ] }
  end

  test "止まった running は積み直す" do
    Translation.create!(story: @story, status: "running", updated_at: 20.minutes.ago)
    assert_enqueued_jobs(1, only: TranslateStoryJob) { post story_translation_path(@story) }
  end

  test "本文が無ければ積まない" do
    @story.update!(content: nil)
    assert_no_enqueued_jobs(only: TranslateStoryJob) { post story_translation_path(@story) }
    assert_nil @story.translation
  end

  test "running や done なら積まない" do
    Translation.create!(story: @story, status: "running")
    assert_no_enqueued_jobs(only: TranslateStoryJob) { post story_translation_path(@story) }
    @story.translation.update!(status: "done")
    assert_no_enqueued_jobs(only: TranslateStoryJob) { post story_translation_path(@story) }
  end
end
