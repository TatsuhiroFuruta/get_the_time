class ConvertRemainingTimeToSeconds < ActiveRecord::Migration[8.1]
  def up
    PurificationTime.find_each do |pt|
      pt.update_columns(
        remaining_time: pt.remaining_time * 60,
        total_time: pt.total_time * 60
      )
    end
  end

  def down
    PurificationTime.find_each do |pt|
      pt.update_columns(
        remaining_time: pt.remaining_time / 60,
        total_time: pt.total_time / 60
      )
    end
  end
end
