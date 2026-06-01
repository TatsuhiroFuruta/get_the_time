class MystatusesController < ApplicationController
  DAYS = 14

  def show
    @daily_series = build_daily_series(current_user, days: DAYS)
    @evaluation_averages = ActivityRecord.evaluation_averages(current_user, days: DAYS)
    @fatigue_average = ActivityRecord.fatigue_average(current_user, days: DAYS)
    # 0〜1 の生の平均をそのまま渡し、パーセント表記はビューの display_percentage に委譲（記録なしは nil）
    @desired_self_percentage_average = ActivityRecord.desired_self_percentage_average(current_user, days: DAYS)
  end

  private

  # daily_series を直近 DAYS 日の枠に展開し、欠損日は light_time_minutes=0, desired_self_percentage=nil で埋める
  # desired_self_percentage は 0〜100 のパーセント表記に変換
  def build_daily_series(user, days:)
    raw = ActivityRecord.daily_series(user, days: days)
    by_date = raw.index_by { |row| row[:date] }
    start_date = (days - 1).days.ago.in_time_zone.to_date

    (0...days).map do |i|
      date = start_date + i
      row = by_date[date]
      {
        date: date,
        light_time_minutes: row ? row[:light_time_minutes] : 0,
        desired_self_percentage: row && row[:desired_self_percentage] ? (row[:desired_self_percentage] * 100).round(1) : nil
      }
    end
  end
end
