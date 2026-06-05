class AddFavoritedToRegretRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :regret_records, :favorited, :boolean, default: false, null: false
  end
end
