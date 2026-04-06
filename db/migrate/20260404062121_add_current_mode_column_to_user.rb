class AddCurrentModeColumnToUser < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :current_mode, :integer, default: 0, null: false
  end
end
