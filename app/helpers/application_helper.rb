module ApplicationHelper
  def format_datetime(dt)
    dt&.in_time_zone("Tokyo")&.strftime("%Y-%m-%d %H:%M")
  end

  def display_percentage(value)
    return "未設定" if value.blank?

    "#{(value * 100).round} %"
  end
end
