class CreatePomodoroSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :pomodoro_settings do |t|
      t.integer :work_duration, null: false, default: 25
      t.integer :break_duration, null: false, default: 5
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.timestamps
    end

    # 既存ユーザーに対してデフォルト値でレコードを生成
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO pomodoro_settings (user_id, work_duration, break_duration, created_at, updated_at)
          SELECT id, 25, 5, NOW(), NOW() FROM users
        SQL
      end
    end
  end
end
