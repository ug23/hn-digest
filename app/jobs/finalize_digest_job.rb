# 毎朝 06:00(Asia/Tokyo)に、前回の確定以降に閾値を超えた記事を当日分として確定する。
class FinalizeDigestJob < ApplicationJob
  queue_as :default

  def perform
    profile = Profile.current
    return unless profile

    ids = Story.joins(:evaluations)
               .where(digested_on: nil, evaluations: { profile_id: profile.id, status: "scored" })
               .where("evaluations.score >= ?", profile.score_threshold).pluck(:id)

    date = Date.current
    Story.where(id: ids).update_all(digested_on: date)
    # Push 通知用のフック。将来ここを購読して通知を足す（今回は購読者を作らない）
    ActiveSupport::Notifications.instrument("digest_finalized.hn_digest", date: date, story_ids: ids)
  end
end
