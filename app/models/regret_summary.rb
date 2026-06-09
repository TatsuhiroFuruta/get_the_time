class RegretSummary < ApplicationRecord
  validates :content, presence: true
  validates :user_id, uniqueness: true

  belongs_to :user
end
