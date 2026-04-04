class ActivityRecord < ApplicationRecord
  belongs_to :user
  belongs_to :light_time

  before_save :calculate_desired_self_percentage
  after_create :grant_purification_time

  # 浄化タイマーの時間計算メソッド
  def self.calculate_purification_time(total_duration)
    # return 0 if total_duration.blank? || total_duration < 10
    return 0 if total_duration.blank? || total_duration < 1

    # 確認用
    (total_duration / 2).floor * 1
    # 本番用
    # (total_duration / 30).floor * 10
  end

  # 検索可能カラムの登録
  def self.ransackable_attributes(auth_object = nil)
    ["comment"]  # 検索可能なカラム
  end

  # 検索可能な関連付けをホワイトリスト化
  def self.ransackable_associations(auth_object = nil)
    ["light_time"]
  end

  private

  # 今日の本来の自分を算出メソッド
  def calculate_desired_self_percentage
    return if total_duration.to_i == 0

    self.desired_self_percentage = (total_duration - idle_duration).to_f / total_duration
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
