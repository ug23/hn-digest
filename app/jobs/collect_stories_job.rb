# 毎時5分に Solid Queue のスケジューラ（config/recurring.yml）が積む。
class CollectStoriesJob < ApplicationJob
  queue_as :default

  def perform
    rows = Hn.search_stories.select { |hit| hit["title"].present? }.map { |hit| Hn.story_attributes(hit) }
    # 既存の行は points と num_comments だけを更新する（hn_id の一意索引で衝突を判定）
    Story.upsert_all(rows, unique_by: :hn_id, update_only: %i[points num_comments]) if rows.any?

    # 以降は毎時の掃き直しを兼ねる。ollama が止まっていた間の記事も次の回で拾われる
    # 掃き直しは直近7日の記事だけにする。プロファイルの版が増えても全履歴が LLM に流れないようにするため
    recent = Story.where(posted_at: 7.days.ago..)
    recent.fetchable.find_each { |story| FetchStoryJob.perform_later(story) }

    profile = Profile.current
    return unless profile

    evaluated = Evaluation.where(profile: profile).select(:story_id)
    recent.where(content_status: %w[fetched failed]).where.not(id: evaluated).find_each do |story|
      EvaluateStoryJob.perform_later(story, profile)
    end

    # 閾値以上なのに要約が無い記事(ollama が止まっていた間の取りこぼし)にも要約を積む
    above = Evaluation.where(profile: profile, status: "scored").where("score >= ?", profile.score_threshold).select(:story_id)
    recent.where(id: above).where.not(id: Summary.select(:story_id)).find_each { |story| SummarizeStoryJob.perform_later(story) }
  end
end
