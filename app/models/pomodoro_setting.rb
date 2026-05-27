class PomodoroSetting < ApplicationRecord
  WORK_DURATION_RANGE = 10..90
  BREAK_DURATION_RANGE = 1..30

  belongs_to :user

  validates :work_duration,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: WORK_DURATION_RANGE.min,
              less_than_or_equal_to: WORK_DURATION_RANGE.max
            }
  validates :break_duration,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: BREAK_DURATION_RANGE.min,
              less_than_or_equal_to: BREAK_DURATION_RANGE.max
            }
  validate :break_duration_must_be_less_than_work_duration

  private

  def break_duration_must_be_less_than_work_duration
    return if work_duration.blank? || break_duration.blank?

    if break_duration >= work_duration
      errors.add(:break_duration, "は活動時間未満で設定してください")
    end
  end
end
