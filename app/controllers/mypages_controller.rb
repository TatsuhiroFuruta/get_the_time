class MypagesController < ApplicationController
  before_action :authenticate_user!

  def show
    @dark_time = current_user.dark_time
  end
end
