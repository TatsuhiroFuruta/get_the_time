class CreateLightTimes < ActiveRecord::Migration[8.1]
  def change
    create_table :light_times do |t|
      t.text :action, null: false
      t.text :desired_self
      t.text :characteristic
      t.boolean :is_current, null: false, default: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
