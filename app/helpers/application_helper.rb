module ApplicationHelper
  def format_datetime(dt)
    dt&.in_time_zone("Tokyo")&.strftime("%Y-%m-%d %H:%M")
  end
end
