class LightTimesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_light_time, only: %i[show edit update destroy switch]

  def switch
    return head :not_found unless @light_time

    LightTime.switch_current!(current_user, @light_time)

    respond_to do |format|
      format.turbo_stream
    end
  end

  def new
    @light_time = current_user.light_times.build
  end

  def create
    @light_time = current_user.light_times.build(light_time_params)
    if @light_time.save
      LightTime.switch_current!(current_user, @light_time)
      redirect_to mypage_path, notice: t('defaults.flash_message.created', item: LightTime.model_name.human)
    else
      flash.now[:alert] = t('defaults.flash_message.not_created', item: LightTime.model_name.human)
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  def update
    if @light_time.update(light_time_params)
      redirect_to light_time_path(@light_time), notice: t('defaults.flash_message.updated', item: LightTime.model_name.human)
    else
      flash.now[:alert] = t('defaults.flash_message.not_updated', item: LightTime.model_name.human)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    was_current = @light_time.is_current
    @light_time.destroy!

    if was_current
      next_light_time = current_user.light_times.order(:created_at).first
      LightTime.switch_current!(current_user, next_light_time) if next_light_time
    end

    redirect_to mypage_path, notice: t('defaults.flash_message.deleted', item: LightTime.model_name.human), status: :see_other
  end

  private

  def set_light_time
    @light_time = current_user.light_times.find(params[:id])
  end

  def light_time_params
    # is_currentはフォームから渡さないため、追加しない。むしろ追加しない方が安全
    params.require(:light_time).permit(:action, :desired_self, :characteristic)
  end
end
