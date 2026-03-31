class CreatePurificationTimes < ActiveRecord::Migration[8.1]
  def change
    create_table :purification_times do |t|
      t.integer :status
      t.integer :remaining_time
      t.integer :total_time
      t.datetime :started_at
      t.datetime :paused_at
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.timestamps
    end
  end
end
