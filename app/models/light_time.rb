class LightTime < ApplicationRecord
  validates :action, presence: true

  belongs_to :user

  def self.switch_current!(user, light_time)
    transaction do
      user.light_times.update_all(is_current: false)
      light_time.update!(is_current: true)
    end
  end
end
