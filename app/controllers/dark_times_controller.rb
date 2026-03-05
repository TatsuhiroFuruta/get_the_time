class DarkTimesController < ApplicationController
  before_action :authenticate_user!

  def new
    @dark_time = current_user.build_dark_time
  end

  def create
    @dark_time = current_user.build_dark_time(dark_time_params)
    if @dark_time.save
      redirect_to mypage_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @dark_time = current_user.dark_time
  end

  def dark_time_params
    params.require(:dark_time).permit(:behavior, :unwanted_future, :characteristic)
  end
end
