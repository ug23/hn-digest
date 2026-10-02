class LabelingsController < ApplicationController
  # 現行プロファイルの評価が直近7日にあり、まだ 👍👎 を付けていない記事。filtered / excluded も含める(取りこぼしを見つけるため)
  def show
    @evaluations = Evaluation.includes(story: [ :feedback, :summary ])
                             .where(profile: Profile.current, created_at: 7.days.ago..)
                             .where.not(story_id: Feedback.where.not(rating: nil).select(:story_id))
                             .order(created_at: :desc).limit(50)
  end
end
