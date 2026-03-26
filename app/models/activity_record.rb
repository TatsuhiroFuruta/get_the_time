class ActivityRecord < ApplicationRecord
  belongs_to :user
  belongs_to :light_time

  before_save :calculate_desired_self_percentage

  def calculate_desired_self_percentage
    return if total_duration.to_i == 0

    self.desired_self_percentage =
      (total_duration - idle_duration).to_f / total_duration
  end

  # 検索可能カラムの登録
  def self.ransackable_attributes(auth_object = nil)
    ["comment"]  # 検索可能なカラム
  end

  # 検索可能な関連付けをホワイトリスト化
  def self.ransackable_associations(auth_object = nil)
    ["light_time"]
  end
end
