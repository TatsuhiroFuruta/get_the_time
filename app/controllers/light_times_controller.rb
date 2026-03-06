class LightTimesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_light_time, only: [:show, :edit, :update, :destroy]

  def new
    @light_time = current_user.light_times.build
  end

  def create
    @light_time = current_user.light_times.build(light_time_params)
    if @light_time.save
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
    @light_time.destroy!
    redirect_to mypage_path, status: :see_other
  end

  private

  def set_light_time
    @light_time = current_user.light_times.find(params[:id])
  end

  def light_time_params
    params.require(:light_time).permit(:action, :desired_self, :characteristic)
  end
end
