class MypagesController < ApplicationController
  def show
    @dark_time = current_user.dark_time
    @light_time = current_user.light_times.find_by(is_current: true) || current_user.light_times.first
    @purification_time = current_user.purification_time
    @today_light_time = ActivityRecord.total_light_time_today(current_user)
    @pomodoro_setting = current_user.pomodoro_setting

    # 別タブで光の時間の活動中だったため、クライアント側のガードに追い返された場合。
    # サーバの状態からは判定できないので、クエリパラメータで理由を受け取る。
    flash.now[:alert] = t("mypages.flash_message.activity_locked") if params[:locked] == "activity"
  end
end
