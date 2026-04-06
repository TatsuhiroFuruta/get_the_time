class PurificationTimesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_purification_time

  def show; end

  def start
    @purification_time.start!
    head :ok
  end

  def stop
    @purification_time.stop!
    head :ok
  end

  def reset
    unless @purification_time.running?
      @purification_time.reset!
      head :ok
    else
      redirect_to mypage_path, alert: "タイマー実行中です"
    end
  end

  private

  def set_purification_time
    @purification_time = current_user.purification_time
  end
end
