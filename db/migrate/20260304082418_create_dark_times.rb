class CreateDarkTimes < ActiveRecord::Migration[8.1]
  def change
    create_table :dark_times do |t|
      t.text :behavior, null: false
      t.text :unwanted_future
      t.text :characteristic
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
