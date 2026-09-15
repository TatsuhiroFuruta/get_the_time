# ゲストユーザーとデモデータ一式を単一トランザクションで作るサービス。
#
# 関連データは insert_all! でまとめて入れる。1件ずつ create! すると活動記録だけで
# 30往復になり、ネットワーク越しの Neon ではログインの待ち時間に直結する
# （往復20msなら約0.6秒）。insert_all! なら生成全体が約10クエリに収まる。
#
# insert_all! はバリデーションもコールバックも飛ばすため、5段階評価・idle_duration・
# desired_self_percentage は GuestDemoData 側で担保している。
class GuestUserBuilder
  def self.call
    new.call
  end

  def call
    User.transaction do
      user = create_user
      light_time_ids = create_light_times(user)
      user.create_dark_time!(GuestDemoData.dark_time)
      insert_activity_records(user, light_time_ids)
      insert_regret_records(user)
      user.create_regret_summary!(GuestDemoData.regret_summary.merge(generated_at: Time.current))
      user.create_purification_time!(GuestDemoData.purification_time)
      user
    end
  end

  private

  def create_user
    # last_request_at を必ず入れる。nil のままだと削除条件 last_request_at < ? に
    # 永久にマッチせず、そのゲストが一度も削除されない。
    User.create!(
      guest: true,
      email: "guest_#{SecureRandom.hex(8)}@example.com",
      password: SecureRandom.hex(16),
      name: "ゲストユーザー",
      last_request_at: Time.current
    )
  end

  # current の設定は LightTime.switch_current! に通す。「ちょうど 1 件 current」の
  # 不変条件をこのメソッドが担保しているため、is_current を直接書かない。
  def create_light_times(user)
    light_times = GuestDemoData.light_times.map { |attrs| user.light_times.create!(attrs) }
    LightTime.switch_current!(user, light_times.first)

    light_times.map(&:id)
  end

  def insert_activity_records(user, light_time_ids)
    now = Time.current
    rows = GuestDemoData.activity_records(now).map do |attrs|
      attrs = attrs.dup
      light_time_id = light_time_ids.fetch(attrs.delete(:light_time_index))

      attrs.merge(user_id: user.id, light_time_id: light_time_id, created_at: now, updated_at: now)
    end

    ActivityRecord.insert_all!(rows)
  end

  def insert_regret_records(user)
    now = Time.current
    rows = GuestDemoData.regret_records(now).map do |attrs|
      attrs.merge(user_id: user.id, updated_at: now)
    end

    RegretRecord.insert_all!(rows)
  end
end
