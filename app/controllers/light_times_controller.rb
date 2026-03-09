class LightTimesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_light_time, only: %i[show edit update destroy switch]

  def switch
    logger.debug("switchメソッドに入りました")
    logger.debug(params[:id])
    logger.debug(@light_time)
    return head :not_found unless @light_time

    logger.debug(@light_time.is_current)
    LightTime.switch_current!(current_user, @light_time)

    logger.debug(@light_time.is_current)
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
      redirect_to mypage_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  def update
    if @light_time.update(light_time_params)
      redirect_to light_time_path(@light_time)
    else
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

    redirect_to mypage_path, status: :see_other
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
