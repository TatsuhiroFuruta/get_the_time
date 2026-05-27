class PomodoroSettingsController < ApplicationController
  def update
    @pomodoro_setting = current_user.pomodoro_setting

    if @pomodoro_setting.update(pomodoro_setting_params)
      redirect_to mypage_path, notice: t("defaults.flash_message.updated", item: PomodoroSetting.model_name.human)
    else
      redirect_to mypage_path, alert: @pomodoro_setting.errors.full_messages.to_sentence
    end
  end

  private

  def pomodoro_setting_params
    params.require(:pomodoro_setting).permit(:work_duration, :break_duration)
  end
end
