class DarkTime < ApplicationRecord
  validates :behavior, presence: true

  belongs_to :user
end
