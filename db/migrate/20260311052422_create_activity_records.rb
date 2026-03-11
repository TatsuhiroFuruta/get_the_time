class CreateActivityRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_records do |t|
      t.datetime :started_at
      t.datetime :ended_at
      t.text :task
      t.integer :total_duration
      t.integer :idle_duration
      t.integer :satisfaction
      t.integer :progress
      t.integer :quality
      t.integer :focus
      t.integer :fatigue
      t.text :comment
      t.decimal :desired_self_percentage, precision: 5, scale: 2
      t.references :user, null: false, foreign_key: true
      t.references :light_time, null: false, foreign_key: true

      t.timestamps
    end
  end
end
