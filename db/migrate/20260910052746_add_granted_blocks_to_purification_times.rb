class AddGrantedBlocksToPurificationTimes < ActiveRecord::Migration[8.1]
  def change
    # 浄化タイマーを「その日に何ブロック払い出したか」の台帳。
    # 当日累計はレコードから導出できるが、活動記録が削除されると減るため、
    # 累計だけを見ていると同じ 30 分ぶんを何度も付与できてしまう。
    # 払い出した実績はここに残し、削除の影響を受けないようにする。
    add_column :purification_times, :granted_blocks_date, :date
    add_column :purification_times, :granted_blocks_count, :integer, default: 0, null: false
  end
end
