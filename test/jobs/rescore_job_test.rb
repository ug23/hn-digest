require "test_helper"

class RescoreJobTest < ActiveJob::TestCase
  test "cutoff 未満を先に、埋め込みの無い記事を最後に積む" do
    profile = build_profile(embedding_vector: [ 1.0, 0.0 ])
    # 30件以上ないと cutoff が出ないので、類似度が 0.0 から 1.0 へ上がる30件に、埋め込み無しを1件足す
    stories = (0..29).map { |i| build_story(content_status: "fetched", posted_at: i.hours.ago, embedding_vector: [ Math.cos(i * 0.05), Math.sin(i * 0.05) ]) }
    plain = build_story(content_status: "fetched", posted_at: 1.minute.ago)
    RescoreJob.perform_now(profile)

    enqueued = enqueued_jobs.map { |j| j["arguments"] }
    assert_equal 31, enqueued.size
    cutoffs = enqueued.map { |a| a[2] }.uniq
    assert_equal 1, cutoffs.size
    assert_in_delta cutoffs.first, Embeddable.cosine(stories[14].embedding_vector, [ 1.0, 0.0 ]) / 2 + Embeddable.cosine(stories[15].embedding_vector, [ 1.0, 0.0 ]) / 2, 1e-6
    ids = enqueued.map { |a| a[0]["_aj_globalid"][/\d+\z/].to_i }
    assert_equal plain.id, ids.last
    assert_equal stories[15..].map(&:id).sort, ids[0, 15].sort # 類似度の低い半分(i が大きい方)が先
  end
end
