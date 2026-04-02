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

  private

  def set_purification_time
    @purification_time = current_user.purification_time
  end
end
