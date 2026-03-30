module ApplicationHelper
  def format_datetime(dt)
    dt&.in_time_zone("Tokyo")&.strftime("%Y-%m-%d %H:%M")
  end

  def display_percentage(value)
    return "未設定" if value.blank?

    "#{(value * 100).round} %"
  end

  def nav_link_class(path)
    base = "block py-2 text-center border-t border-amber-500"
    active = "bg-linear-to-b from-yellow-200 from-0% via-yellow-300 via-80% to-yellow-600 to-100%"
    inactive = "bg-yellow-200"

    current_page?(path) ? "#{base} #{active}" : "#{base} #{inactive}"
  end
end
