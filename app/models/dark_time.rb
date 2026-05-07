class DarkTime < ApplicationRecord
  validates :behavior, presence: true
  validates :user_id, uniqueness: true

  belongs_to :user
end
