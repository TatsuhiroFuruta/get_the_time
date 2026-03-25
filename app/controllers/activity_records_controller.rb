class ActivityRecordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_times, only: %i[new create]

  def index
    @activity_records = current_user.activity_records.includes(:light_time).order(created_at: :desc)
  end

  def new
    unless params[:activity_record_form].present?
      # redirect_to pomodoro_timer_activity_records_path, alert: "ポモドーロタイマーからアクセスしてください"
      redirect_to pomodoro_timer_activity_records_path
      return
    end
    @form = ActivityRecordForm.new(activity_record_form_params)
  end

  def create
    @form = ActivityRecordForm.new(activity_record_form_params)

    if @form.save(current_user)
      redirect_to activity_records_path
    else
      @light_time = current_user.light_times.find_by(is_current: true)
      @dark_time = current_user.dark_time
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @activity_record = current_user.activity_records.find(params[:id])
  end

  def pomodoro_timer
    # タスク内容を登録のためこちらでインスタンス化
    @activity_record = current_user.activity_records.build(task: params[:task])
    @light_time = current_user.light_times.find_by(is_current: true)
    @dark_time = current_user.dark_time
  end

  private

  def set_times
    @light_time = current_user.light_times.find_by(is_current: true)
    @dark_time = current_user.dark_time
  end

  def activity_record_form_params
    params.require(:activity_record_form).permit(
    :started_at, :ended_at, :task, :total_duration,
    :idle_duration, :satisfaction, :progress,
    :quality, :focus, :fatigue, :comment,
    :light_time_characteristic, :dark_time_characteristic
    )
  end
end
