# 活動記録の登録に伴う浄化タイマー時間の付与をまとめるサービス。
#
# 書き込み経路をオブジェクトに集約する流儀（app/forms/activity_record_form.rb）に倣い、
# 付与分数の計算（ActivityRecord.calculate_purification_time）と PurificationTime への
# 加算・保存をここに閉じ込める。付与した分数を戻り値として返すため、フラッシュ表示など
# 呼び出し側が「実際に付与した値」をそのまま利用でき、再計算による表示と保存のズレを防ぐ。
#
# 付与分数は 30 分ブロックごとの重み付き抽選（乱数）で決まるため、計算は必ず 1 回だけ行う。
class PurificationTimeGranter
  def initialize(user)
    @user = user
  end

  # total_duration（分）に応じた浄化タイマー時間を付与し、付与した分数を返す。
  # 付与が発生しないときは 0 を返す。
  def call(total_duration)
    minutes = ActivityRecord.calculate_purification_time(total_duration)
    return 0 if minutes <= 0

    @user.with_lock do
      purification_time = @user.purification_time || @user.build_purification_time
      purification_time.remaining_time += minutes * 60
      purification_time.save!
    end

    minutes
  end
end
