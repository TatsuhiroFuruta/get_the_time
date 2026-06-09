class CreateRegretSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :regret_summaries do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :content, null: false
      t.datetime :generated_at, null: false

      t.timestamps
    end
  end
end
