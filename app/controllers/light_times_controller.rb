class LightTimesController < ApplicationController
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

  def show
    @light_time = current_user.light_times.find(params[:id])
  end

  private

  def light_time_params
    params.require(:light_time).permit(:action, :desired_self, :characteristic)
  end
end
