class Evaluation < ApplicationRecord
  belongs_to :story
  belongs_to :profile

  # その版の閾値以上か。再採点の表で、閾値をまたいだ行を強調するのに使う
  def above_threshold?
    status == "scored" && score >= profile.score_threshold
  end
end
