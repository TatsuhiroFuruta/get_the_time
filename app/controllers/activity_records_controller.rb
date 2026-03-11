class ActivityRecordsController < ApplicationController
  before_action :authenticate_user!

  def pomodoro_timer
    @light_time = current_user.light_times.find_by(is_current: true)
  end
end
