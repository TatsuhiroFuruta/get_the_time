class PurificationTimesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_purification_time
  before_action :ensure_can_start_purification, only: %i[start]

  def show; end

  def start
    @purification_time.start!
    current_user.update!(current_mode: :purification)
    head :ok
  end

  def stop
    @purification_time.stop!
    current_user.update!(current_mode: :idle)
    head :ok
  end

  def reset
    @purification_time.reset!
    head :ok
  end

  private

  def set_purification_time
    @purification_time = current_user.purification_time
  end

  def ensure_can_start_purification
    return if current_user.can_start_purification?
    redirect_to mypage_path, alert: "タイマー実行中です"
    return
  end
end
