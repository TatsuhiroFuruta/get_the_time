class ActivityRecordForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # ===== ActivityRecord =====
  attr_accessor :task, :comment

  # ===== 他モデル =====
  attr_accessor :light_time_characteristic, :dark_time_characteristic

  # ===== バリデーション判定で整数型として用いるため、attributeで登録 =====
  attribute :started_at, :datetime
  attribute :ended_at, :datetime
  attribute :total_duration, :integer
  attribute :idle_duration, :integer
  attribute :satisfaction, :integer
  attribute :progress, :integer
  attribute :quality, :integer
  attribute :focus, :integer
  attribute :fatigue, :integer

  # ===== バリデーション =====
  validates :idle_duration, numericality: { greater_than_or_equal_to: 0 }
  validate :idle_duration_cannot_exceed_total_duration

  validates :satisfaction, :progress, :quality, :focus, :fatigue, inclusion: { in: 1..5 }

  # ===== 保存処理 =====
  def save(user)
    return false unless valid?

    ActiveRecord::Base.transaction do
      light_time = user.light_times.find_by(is_current: true)

      # ActivityRecord 作成
      user.activity_records.create!(
        started_at: started_at,
        ended_at: ended_at,
        task: task,
        total_duration: total_duration,
        idle_duration: idle_duration,
        satisfaction: satisfaction,
        progress: progress,
        quality: quality,
        focus: focus,
        fatigue: fatigue,
        comment: comment,
        light_time: light_time
      )

      # Rails.logger.debug "ActivityRecord OK"

      # LightTime 更新
      user.light_times.find_by(is_current: true)&.update!(
        characteristic: light_time_characteristic
      )

      # Rails.logger.debug "LightTime OK"

      # DarkTime 更新
      user.dark_time&.update!(
        characteristic: dark_time_characteristic
      )

      # Rails.logger.debug "DarkTime OK"
    end

    true
  rescue ActiveRecord::RecordInvalid
  # rescue => e
    # Rails.logger.debug "SAVE ERROR: #{e.message}"
    false
  end

  private

  def idle_duration_cannot_exceed_total_duration
    return if idle_duration.blank? || total_duration.blank?

    if idle_duration > total_duration
      errors.add(:idle_duration, "は合計時間以下にしてください")
    end
  end
end
