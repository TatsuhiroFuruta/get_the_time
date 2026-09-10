# 活動記録の登録に伴う浄化タイマー時間の付与をまとめるサービス。
#
# 付与の単位は「その日の光の時間の累計 30 分ごとに 1 ブロック」。その日の累計から求めた
# ブロック数と、`purification_times` に記録した払い出し済みブロック数の差を取り、
# まだ払い出していない分だけを付与する。
#
# 累計は活動記録から導出するので、記録が削除されると減る。払い出し済み数まで累計から
# 導出すると、29 分ためた状態で 1 分の記録を作っては消す操作で 1 分ごとに 1 ブロック
# 稼げてしまうため、払い出した実績だけは台帳として保存する。
#
# 付与分数は 30 分ブロックごとの重み付き抽選（乱数）で決まるため、計算は必ず 1 回だけ行う。
# 付与した分数を戻り値として返すため、フラッシュ表示など呼び出し側が「実際に付与した値」を
# そのまま利用でき、再計算による表示と保存のズレを防ぐ。
class PurificationTimeGranter
  def initialize(user)
    @user = user
  end

  # 保存済みの activity_record を受け取り、その日の累計に応じた浄化タイマー時間を
  # 付与して、付与した分数を返す。付与が発生しないときは 0 を返す。
  #
  # 累計と台帳の読み取りから加算までを with_lock の中で行う。読み取りをロックの外に置くと、
  # 2 件の活動記録が同時に保存されたときに両方が同じ値を読み、同じブロックを二重に
  # 付与しうる。
  def call(activity_record)
    @user.with_lock do
      day = ActivityRecord.activity_date(activity_record)
      purification_time = @user.purification_time || @user.build_purification_time
      granted = purification_time.granted_blocks_for(day)

      blocks = unpaid_blocks(day, granted)
      next 0 if blocks <= 0

      minutes = ActivityRecord.sample_purification_minutes_for(blocks)
      purification_time.remaining_time      += minutes * 60
      purification_time.granted_blocks_date  = day
      purification_time.granted_blocks_count = granted + blocks
      purification_time.save!
      minutes
    end
  end

  private

  # その日の累計から求めたブロック数のうち、まだ払い出していない分。
  # 削除で累計が下がっても払い出し済み数は減らないため、負にならないよう 0 で止める。
  def unpaid_blocks(day, granted)
    total = ActivityRecord.total_light_time_on(@user, day)

    [ ActivityRecord.purification_blocks(total) - granted, 0 ].max
  end
end
