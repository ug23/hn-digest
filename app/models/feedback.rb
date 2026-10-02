class Feedback < ApplicationRecord
  belongs_to :story

  validates :rating, inclusion: { in: [ 1, -1 ] }, allow_nil: true
end
