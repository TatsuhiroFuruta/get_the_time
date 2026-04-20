class PurificationTimesController < ApplicationController
  before_action :set_purification_time

  def show
    respond_to do |format|
      format.html
      format.json do
        render json: {
          running: @purification_time.running?
        }
      end
    end
  end

  def start
    @purification_time.start!
    head :ok
  end

  def stop
    @purification_time.stop!
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
end
