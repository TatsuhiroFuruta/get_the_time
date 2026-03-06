class LightTime < ApplicationRecord
  validates :action, presence: true

  belongs_to :user
end
