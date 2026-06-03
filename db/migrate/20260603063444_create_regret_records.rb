class CreateRegretRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :regret_records do |t|
      t.references :user, null: false, foreign_key: true
      t.text :title
      t.text :content, null: false

      t.timestamps
    end
  end
end
