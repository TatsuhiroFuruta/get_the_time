class ActivityRecord < ApplicationRecord
  belongs_to :user
  belongs_to :light_time

  before_save :calculate_desired_self_percentage

  def calculate_desired_self_percentage
    return if total_duration.to_i == 0

    self.desired_self_percentage =
      (total_duration - idle_duration).to_f / total_duration
  end
end
