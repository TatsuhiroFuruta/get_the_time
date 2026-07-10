class LightTime < ApplicationRecord
  validates :action, presence: true

  belongs_to :user
  has_many :activity_records, dependent: :destroy

  # 切り替え先をリセット対象から除外する。update_all はメモリ上の light_time を
  # 更新しないため、対象を含めてしまうと「メモリ上は既に true」の場合に
  # update! が差分なしと判断して UPDATE を発行せず、current が 0 件になる。
  def self.switch_current!(user, light_time)
    transaction do
      user.light_times.where.not(id: light_time.id).update_all(is_current: false)
      light_time.update!(is_current: true)
    end
  end

  # current の光の時間を削除した場合は最古のレコードを current に昇格させ、
  # 「ちょうど 1 件 current」の不変条件を維持する。削除と昇格を単一トランザクションで
  # まとめることで、途中失敗による「削除済みだが current 不在」の状態を防ぐ。
  def self.destroy_with_current_reassignment!(user, light_time)
    transaction do
      was_current = light_time.is_current
      light_time.destroy!

      if was_current
        next_light_time = user.light_times.order(:created_at).first
        switch_current!(user, next_light_time) if next_light_time
      end
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "action" ]  # 検索可能なカラム
  end
end
