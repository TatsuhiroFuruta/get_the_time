class AddDefaultToPurificationTimes < ActiveRecord::Migration[8.1]
  def change
    change_column_default :purification_times, :remaining_time, 0
    change_column_default :purification_times, :total_time, 0

    change_column_null :purification_times, :remaining_time, false
    change_column_null :purification_times, :total_time, false
  end
end
