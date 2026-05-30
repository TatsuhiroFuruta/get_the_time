class ActivityRecord < ApplicationRecord
  belongs_to :user
  belongs_to :light_time

  before_save :calculate_desired_self_percentage
  after_create :grant_purification_time

  # ===== バリデーション =====
  validates :idle_duration, numericality: { greater_than_or_equal_to: 0 }
  validate :idle_duration_cannot_exceed_total_duration

  validates :satisfaction, :progress, :quality, :focus, :fatigue, inclusion: { in: 1..5 }

  # レーダーチャート対象の5段階評価カラム（疲労感は逆指標のため別集計）
  RADAR_FIELDS = %i[satisfaction progress quality focus].freeze

  scope :today, -> {
    where(created_at: Time.current.all_day)
  }

  scope :within_last_days, ->(days) {
    where(created_at: days.days.ago.beginning_of_day..)
  }

  def self.total_light_time_today(user)
    where(user: user)
      .today
      .sum(:total_duration)
      .to_i
  end

  # レーダーチャート用: 直近N日の5段階評価4項目の平均
  def self.evaluation_averages(user, days: 30)
    records = user.activity_records.within_last_days(days)
    RADAR_FIELDS.index_with { |field| records.average(field)&.to_f }
  end

  # 直近N日の疲労感の平均（逆指標のためレーダーから分離）
  def self.fatigue_average(user, days: 30)
    user.activity_records.within_last_days(days).average(:fatigue)&.to_f
  end

  # 直近N日の本来の自分の平均（全レコード平均）
  def self.desired_self_percentage_average(user, days: 30)
    user.activity_records.within_last_days(days).average(:desired_self_percentage)&.to_f
  end

  # 時系列グラフ用: 直近N日の日次集計（JST基準）
  # light_time_minutes は SUM(total_duration) の合計分数（total_duration は分単位で保存されている）
  # 該当レコードがない日は配列に含まれない
  def self.daily_series(user, days: 30)
    bucket = Arel.sql("DATE((created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Tokyo')")
    user.activity_records
        .within_last_days(days)
        .group(bucket)
        .order(bucket)
        .pluck(
          bucket,
          Arel.sql("SUM(total_duration)"),
          Arel.sql("AVG(desired_self_percentage)")
        )
        .map do |date, total_duration_sum, desired_self_avg|
          {
            date: date,
            light_time_minutes: total_duration_sum.to_i,
            desired_self_percentage: desired_self_avg&.to_f
          }
        end
  end

  # 付与分数の重み付きテーブル（合計 100）
  PURIFICATION_TIME_TABLE = [
    { minutes: 8,  weight: 60 },
    { minutes: 10, weight: 30 },
    { minutes: 13, weight: 9  },
    { minutes: 15, weight: 1  }
  ].freeze

  # 1ブロック分の付与分数をランダム抽選
  def self.sample_purification_minutes
    threshold = rand(100)
    cumulative = 0
    PURIFICATION_TIME_TABLE.each do |entry|
      cumulative += entry[:weight]
      return entry[:minutes] if threshold < cumulative
    end
    PURIFICATION_TIME_TABLE.last[:minutes]
  end

  # 浄化タイマーの時間計算メソッド（30分ブロックごとにランダム付与）
  def self.calculate_purification_time(total_duration)
    return 0 if total_duration.blank? || total_duration < 1

    blocks = (total_duration / 30).floor
    return 0 if blocks == 0

    blocks.times.sum { sample_purification_minutes }
  end

  # 検索可能カラムの登録
  def self.ransackable_attributes(auth_object = nil)
    [ "comment", "favorited" ]  # 検索可能なカラム
  end

  # 検索可能な関連付けをホワイトリスト化
  def self.ransackable_associations(auth_object = nil)
    [ "light_time" ]
  end

  private

  # 今日の本来の自分を算出メソッド
  def calculate_desired_self_percentage
    return if total_duration.to_i == 0

    self.desired_self_percentage = (total_duration - idle_duration).to_f / total_duration
  end

  def idle_duration_cannot_exceed_total_duration
    return if idle_duration.blank? || total_duration.blank?

    if idle_duration > total_duration
      errors.add(:idle_duration, "は合計時間以下にしてください")
    end
  end

  # 浄化タイマーの時間を付与するメソッド
  def grant_purification_time
    minutes = self.class.calculate_purification_time(total_duration)
    return if minutes <= 0

    user.with_lock do
      purification_time = user.purification_time || user.build_purification_time

      purification_time.remaining_time += minutes * 60

      purification_time.save!
    end
  end
end
