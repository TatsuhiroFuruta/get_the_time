class AddFavoritedToActivityRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :activity_records, :favorited, :boolean, default: false, null: false
  end
end
