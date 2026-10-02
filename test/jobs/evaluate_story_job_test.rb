require "test_helper"

class EvaluateStoryJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  # Ollama.embed と Scorer.call だけを差し替える(外部通信なし)
  def stubbed
    embed, call = Ollama.method(:embed), Scorer.method(:call)
    Ollama.define_singleton_method(:embed) { |texts, **| texts.map { [ 1.0, 0.0 ] } }
    Scorer.define_singleton_method(:call) { |*, **| { llm_score: 8, reasons: [ "理由" ], tags: [], should_read: "yes" } }
    yield
  ensure
    Ollama.define_singleton_method(:embed, embed)
    Scorer.define_singleton_method(:call, call)
  end

  test "前の版が無く broadcast なしでも scored になり、要約が積まれる" do
    story = build_story
    profile = build_profile
    stubbed { assert_no_broadcasts(Turbo::StreamsChannel.send(:stream_name_from, [ profile, :rescore ])) { EvaluateStoryJob.perform_now(story, profile, nil) } }
    assert_equal "scored", Evaluation.find_by(story: story, profile: profile).status
    assert_enqueued_with(job: SummarizeStoryJob, args: [ story ])
  end

  test "broadcast: true は前の版の評価が無い記事でも例外にならず、行を配信する" do
    story = build_story
    profile = build_profile
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ profile, :rescore ])
    stubbed { assert_broadcasts(stream, 1) { EvaluateStoryJob.perform_now(story, profile, nil, broadcast: true) } }
    assert_enqueued_with(job: SummarizeStoryJob)
  end
end
