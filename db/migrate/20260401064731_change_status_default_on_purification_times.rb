class ChangeStatusDefaultOnPurificationTimes < ActiveRecord::Migration[8.1]
  def change
    # 既存データを更新
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE purification_times
          SET status = 0
          WHERE status IS NULL;
        SQL
      end
    end

    change_column_default :purification_times, :status, 0
    change_column_null :purification_times, :status, false
  end
end
