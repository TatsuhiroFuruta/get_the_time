class ActivityRecordsController < ApplicationController
  before_action :authenticate_user!

  def index; end

  def new
    logger.debug(form_params)
    # @activity_record = current_user.activity_records.build(activity_record_params)
    @form = ActivityRecordForm.new(form_params)
    @light_time = current_user.light_times.find_by(is_current: true)
    @dark_time = current_user.dark_time
  end

  def pomodoro_timer
    # タスク内容を登録のためこちらでインスタンス化
    @activity_record = current_user.activity_records.build(task: params[:task])
    @light_time = current_user.light_times.find_by(is_current: true)
    @dark_time = current_user.dark_time
  end

  private

  def activity_record_params
    params.require(:activity_record).permit(:started_at, :ended_at, :task, :total_duration, :idle_duration, :satisfaction, :progress, :quality, :focus, :fatigue, :comment)
  end

  def form_params
    params.fetch(:activity_record_form, {}).permit(
    :started_at, :ended_at, :task, :total_duration,
    :idle_duration, :satisfaction, :progress,
    :quality, :focus, :fatigue, :comment,
    :light_time_characteristic, :dark_time_characteristic
    )
  end
end
