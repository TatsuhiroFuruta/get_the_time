module MypagesHelper
  def both_times_present?(dark_time, light_time)
    dark_time.present? && light_time.present?
  end
end
