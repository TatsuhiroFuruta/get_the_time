class MypagesController < ApplicationController
  before_action :authenticate_user!

  def show
    @dark_time = current_user.dark_time
    @light_time = current_user.light_times.find_by(is_current: true) || current_user.light_times.first
    @purification_time = current_user.purification_time
  end
end
