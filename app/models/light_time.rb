class LightTime < ApplicationRecord
  validates :action, presence: true

  belongs_to :user
  has_many :activity_records, dependent: :destroy

  def self.switch_current!(user, light_time)
    transaction do
      user.light_times.update_all(is_current: false)
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
