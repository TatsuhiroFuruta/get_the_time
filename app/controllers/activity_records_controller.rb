class ActivityRecordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_light_and_dark_times, only: %i[new create]
  before_action :set_activity_record, only: %i[show edit update destroy]

  def index
    # @activity_records = current_user.activity_records.includes(:light_time).order(created_at: :desc)
    @q = current_user.activity_records.ransack(params[:q])
    @activity_records = @q.result(distinct: true).includes(:light_time).order(created_at: :desc).page(params[:page]).per(8)
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
      minutes = ActivityRecord.calculate_purification_time(@form.total_duration)

      # 0分のとき以外のみ追加！
      if minutes > 0
        flash[:purification_time] = "浄化タイマーを#{minutes}分獲得！"
      end

      redirect_to activity_records_path, notice: t('defaults.flash_message.created', item: ActivityRecordForm.model_name.human)
    else
      set_light_and_dark_times
      flash.now[:alert] = t('defaults.flash_message.not_created', item: ActivityRecordForm.model_name.human)
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  def update
    if @activity_record.update(activity_record_params)
      redirect_to activity_record_path(@activity_record), notice: t('defaults.flash_message.updated', item: ActivityRecord.model_name.human)
    else
      flash.now[:alert] = t('defaults.flash_message.not_updated', item: ActivityRecord.model_name.human)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @activity_record.destroy!
    redirect_to activity_records_path, notice: t('defaults.flash_message.deleted', item: ActivityRecord.model_name.human), status: :see_other
  end

  def pomodoro_timer
    # タスク内容を登録のためこちらでインスタンス化
    @activity_record = current_user.activity_records.build(task: params.permit(:task)[:task])
    @light_time = current_user.light_times.find_by(is_current: true)
    @dark_time = current_user.dark_time
  end

  private

  def set_activity_record
    @activity_record = current_user.activity_records.find(params[:id])
  end

  def set_light_and_dark_times
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

  def activity_record_params
    params.require(:activity_record).permit(
    :started_at, :ended_at, :task, :total_duration,
    :idle_duration, :satisfaction, :progress,
    :quality, :focus, :fatigue, :comment
    )
  end
end
