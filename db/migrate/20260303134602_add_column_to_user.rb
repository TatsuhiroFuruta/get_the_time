class AddColumnToUser < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string, null: false, default: ""
  end
end
