class ActivityRecordsController < ApplicationController
  before_action :authenticate_user!

  def index; end

  def new; end

  def pomodoro_timer
    # タスク内容を登録のためこちらでインスタンス化
    @activity_record = current_user.activity_records.build(task: params[:task])
    @light_time = current_user.light_times.find_by(is_current: true)
    @dark_time = current_user.dark_time
  end

  private

  def activity_record_params
    params.require(:activity_record).permit(:task)
  end
end
