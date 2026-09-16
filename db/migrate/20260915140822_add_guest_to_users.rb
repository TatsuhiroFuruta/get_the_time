class AddGuestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :guest, :boolean, default: false, null: false
    add_column :users, :last_request_at, :datetime

    # 削除の絞り込みは「guest かつ last_request_at が古い」のみ。ゲスト行だけを
    # 索引する部分インデックスにして、実ユーザーが増えてもインデックスを小さく保つ。
    add_index :users, :last_request_at, where: "guest"
  end
end
