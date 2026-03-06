class MypagesController < ApplicationController
  before_action :authenticate_user!

  def show
    @dark_time = current_user.dark_time
    @light_time = current_user.light_times.first
  end
end
