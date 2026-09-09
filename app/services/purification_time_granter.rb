# 活動記録の登録に伴う浄化タイマー時間の付与をまとめるサービス。
#
# 付与の単位は「その日の光の時間の累計 30 分ごとに 1 ブロック」。保存した活動記録を
# 含む当日累計と、それを含まない累計のブロック数の差を取ることで、その保存によって
# 新たに越えたぶんだけを付与する。余りを翌日へ繰り越さない設計のため、付与済みの
# ブロック数は累計から導出でき、専用のカラムを持たずに済んでいる。
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
  # 当日累計の読み取りから加算までを with_lock の中で行う。読み取りをロックの外に置くと、
  # 2 件の活動記録が同時に保存されたときに両方が同じ累計を読み、同じブロックを二重に
  # 付与しうる。
  def call(activity_record)
    @user.with_lock do
      blocks = newly_earned_blocks(activity_record)
      next 0 if blocks <= 0

      minutes = ActivityRecord.sample_purification_minutes_for(blocks)
      purification_time = @user.purification_time || @user.build_purification_time
      purification_time.remaining_time += minutes * 60
      purification_time.save!
      minutes
    end
  end

  private

  # 保存後の当日累計と保存前の当日累計の差分ブロック数。
  # total_after は create! の後に取るため activity_record 自身を含んでいる。
  def newly_earned_blocks(activity_record)
    day = ActivityRecord.activity_date(activity_record)
    total_after  = ActivityRecord.total_light_time_on(@user, day)
    total_before = total_after - activity_record.total_duration.to_i

    ActivityRecord.purification_blocks(total_after) - ActivityRecord.purification_blocks(total_before)
  end
end
