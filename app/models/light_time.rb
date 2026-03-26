class LightTime < ApplicationRecord
  validates :action, presence: true

  belongs_to :user
  has_many :activity_records, dependent: :destroy

  def self.switch_current!(user, light_time)
    transaction do
      user.light_times.update_all(is_current: false)
      light_time.update!(is_current: true)
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    ["action"]  # 検索可能なカラム
  end
end
