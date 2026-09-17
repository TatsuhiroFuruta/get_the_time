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
      # generated_at を現在時刻にすると、画面に「生成日時: いま」と出たうえで
      # すぐ下に「デモ用のサンプルです」と書くことになり矛盾する。過去の時刻にする。
      user.create_regret_summary!(GuestDemoData.regret_summary.merge(generated_at: 1.day.ago))
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

  # created_at には ended_at を入れる。全件を同じ Time.current にすると、
  # activity_records#index の order(created_at: :desc) が 30 件すべて同値になり、
  # 並び順が不定になる。Kaminari の LIMIT/OFFSET と組み合わさると、ページをまたいで
  # 同じ記録が重複したり欠けたりする。お気に入りの★を 1 つ押しただけでも行が
  # 書き変わって並びが変わるので、閲覧者にはっきり見える不具合になる。
  #
  # ACTIVITY_AT は COALESCE(ended_at, created_at) で ended_at を優先するため、
  # 日次集計や浄化タイマーの判定には影響しない。「セッションが終わった時刻に記録を
  # 送信した」という意味になり、デモの筋書きとしても自然。
  #
  # light_time_index はデモデータ上の「何番目の光の時間か」で、activity_records には
  # その列が無い。insert_all! はハッシュのキーをそのまま列名として扱うため、実 ID へ
  # 変換したうえでキー自体を落とす必要がある。
  #
  # except / merge はどちらも新しいハッシュを返すので、受け取ったハッシュは壊さない。
  # delete で取り除くと呼び出し元のハッシュを破壊するため、GuestDemoData が毎回新しい
  # ハッシュを返すという実装に依存してしまう。将来メモ化されると、1 人目は成功して
  # 2 人目から落ちる（原因は GuestDemoData 側なのに症状はここに出る）。
  def insert_activity_records(user, light_time_ids)
    now = Time.current
    rows = GuestDemoData.activity_records(now).map do |attrs|
      light_time_id = light_time_ids.fetch(attrs.fetch(:light_time_index))
      recorded_at   = attrs.fetch(:ended_at)

      attrs.except(:light_time_index)
           .merge(user_id: user.id, light_time_id: light_time_id,
                  created_at: recorded_at, updated_at: recorded_at)
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
