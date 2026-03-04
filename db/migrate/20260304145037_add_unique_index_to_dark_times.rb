class AddUniqueIndexToDarkTimes < ActiveRecord::Migration[8.1]
  def change
    remove_index :dark_times, :user_id
    add_index :dark_times, :user_id, unique: true
  end
end
