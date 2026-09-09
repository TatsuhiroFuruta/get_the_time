class ActivityRecord < ApplicationRecord
  belongs_to :user
  belongs_to :light_time

  before_save :calculate_desired_self_percentage

  # ===== バリデーション =====
  validates :idle_duration, numericality: { greater_than_or_equal_to: 0 }
  validate :idle_duration_cannot_exceed_total_duration

  validates :satisfaction, :progress, :quality, :focus, :fatigue, inclusion: { in: 1..5 }

  # レーダーチャート対象の5段階評価カラム（疲労感は逆指標のため別集計）
  RADAR_FIELDS = %i[satisfaction progress quality focus].freeze

  # 「その活動がどの日のものか」を表す式。活動の終了時刻（ended_at）を正とする。
  # created_at は記録の送信時刻なので、0 時をまたぐ活動や後日の登録で実態とずれる。
  # ended_at が未設定のレコードだけ created_at にフォールバックする。created_at は
  # NOT NULL なので、この式が NULL を返して集計から黙って漏れることはない。
  ACTIVITY_AT = "COALESCE(activity_records.ended_at, activity_records.created_at)".freeze

  scope :activity_on, ->(date) {
    range = date.all_day
    where("#{ACTIVITY_AT} BETWEEN ? AND ?", range.begin, range.end)
  }

  scope :today, -> { activity_on(Date.current) }

  scope :within_last_days, ->(days) {
    where("#{ACTIVITY_AT} >= ?", days.days.ago.beginning_of_day)
  }

  # 指定日（JST）の光の時間の合計分数。付与ロジックは「そのレコードの日」を必要とし、
  # 必ずしも今日とは限らないため日付を引数に取る。
  def self.total_light_time_on(user, date)
    where(user: user)
      .activity_on(date)
      .sum(:total_duration)
      .to_i
  end

  def self.total_light_time_today(user)
    total_light_time_on(user, Date.current)
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
    bucket = Arel.sql("DATE((#{ACTIVITY_AT} AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Tokyo')")
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

  # 浄化タイマー付与の 1 ブロック（分）。この分数がたまるごとに抽選を 1 回引く。
  PURIFICATION_BLOCK_MINUTES = 30

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

  # 累計分数から、消化済みのブロック数を求める。
  # 余りを翌日へ繰り越さない設計のため、付与済みブロック数は累計だけから導出できる。
  def self.purification_blocks(minutes)
    [ minutes.to_i, 0 ].max / PURIFICATION_BLOCK_MINUTES
  end

  # blocks 回の抽選を引いた合計分数。乱数を含むため呼ぶたびに結果が変わる。
  def self.sample_purification_minutes_for(blocks)
    return 0 if blocks <= 0

    blocks.times.sum { sample_purification_minutes }
  end

  # 次の付与までの残り分数（マイページ表示用）。累計 0 分でも 30 を返す。
  def self.minutes_until_next_purification(total_minutes)
    PURIFICATION_BLOCK_MINUTES - [ total_minutes.to_i, 0 ].max % PURIFICATION_BLOCK_MINUTES
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
end
