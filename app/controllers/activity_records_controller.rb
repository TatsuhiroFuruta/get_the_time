class ActivityRecordsController < ApplicationController
  before_action :set_light_and_dark_times, only: %i[new create]
  before_action :set_activity_record, only: %i[show edit update destroy favorite]
  before_action :ensure_purification_not_counting, only: %i[pomodoro_timer]

  def index
    @q = current_user.activity_records.ransack(params[:q])
    @activity_records = @q.result(distinct: true).includes(:light_time).order(created_at: :desc).page(params[:page]).per(9)
  end

  def new
    unless params[:activity_record_form].present?
      redirect_to pomodoro_timer_activity_records_path, alert: t("activity_records.flash_message.require_timer_access")
      return
    end
    @form = ActivityRecordForm.new(activity_record_form_params)
  end

  def create
    @form = ActivityRecordForm.new(activity_record_form_params)

    if @form.save(current_user)
      # 付与済みの実値を表示（再計算すると乱数で別の値になり、表示と保存がズレるため）
      minutes = @form.granted_purification_minutes.to_i

      # 0分のとき以外のみ追加！
      if minutes > 0
        flash[:purification_time] = "浄化タイマーを#{minutes}分獲得！"
      end

      redirect_to activity_records_path, notice: t("defaults.flash_message.created", item: ActivityRecordForm.model_name.human)
    else
      set_light_and_dark_times
      flash.now[:alert] = t("defaults.flash_message.not_created", item: ActivityRecordForm.model_name.human)
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  def update
    if @activity_record.update(activity_record_params)
      redirect_to activity_record_path(@activity_record), notice: t("defaults.flash_message.updated", item: ActivityRecord.model_name.human)
    else
      flash.now[:alert] = t("defaults.flash_message.not_updated", item: ActivityRecord.model_name.human)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @activity_record.destroy!
    redirect_to activity_records_path, notice: t("defaults.flash_message.deleted", item: ActivityRecord.model_name.human), status: :see_other
  end

  def favorite
    @activity_record.update!(favorited: !@activity_record.favorited)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to activity_records_path }
    end
  end

  def pomodoro_timer
    @light_time = current_user.light_times.find_by(is_current: true)
    @dark_time = current_user.dark_time

    # 光の時間・闇の時間が揃っていないと画面描画で nil 参照になるため早期リダイレクト。
    # マイページのタイマー起動ボタンと同じガード条件を URL 直打ちにも適用する。
    unless current_user.light_and_dark_times_present?
      redirect_to mypage_path, alert: t("activity_records.flash_message.require_both_times")
      return
    end

    # タスク内容を登録のためこちらでインスタンス化
    @activity_record = current_user.activity_records.build(task: params.permit(:task)[:task])
    @pomodoro_setting = current_user.pomodoro_setting
  end

  private

  # 浄化タイマーが実際に計測中の間は、光の時間の活動を開始させない。
  # 浄化タイマーはタブを閉じても走り続けるサーバ側の状態なので、この向きの
  # ガードはサーバで判定する（クライアントの localStorage では判定できない）。
  def ensure_purification_not_counting
    return unless current_user.purification_time&.counting?

    redirect_to mypage_path, alert: t("activity_records.flash_message.purification_time_counting")
  end

  def not_found_redirect_path
    activity_records_path
  end

  def set_activity_record
    @activity_record = current_user.activity_records.find(params[:id])
  end

  def set_light_and_dark_times
    light_time_id = params.dig(:activity_record_form, :light_time_id)
    @light_time = current_user.light_times.find_by(id: light_time_id)
    @dark_time = current_user.dark_time
  end

  def activity_record_form_params
    params.require(:activity_record_form).permit(
    :started_at, :ended_at, :task, :total_duration,
    :idle_duration, :satisfaction, :progress,
    :quality, :focus, :fatigue, :light_time_id, :comment,
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
