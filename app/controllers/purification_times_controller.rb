class PurificationTimesController < ApplicationController
  before_action :set_purification_time

  def show
    respond_to do |format|
      format.html
      format.json do
        # has_one なので、まだ浄化タイマーを一度も付与されていないユーザーは
        # @purification_time が nil になりうる。ポモドーロ画面の始点チェックが
        # 全ユーザーに対して無条件でこの JSON を叩くため、ここで 500 にしない。
        render json: {
          running: @purification_time&.running? || false,
          counting: @purification_time&.counting? || false
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
