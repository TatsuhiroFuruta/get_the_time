class ActivitiesController < ApplicationController
  before_action :authenticate_user!

  def cancel
    current_user.update!(current_mode: :idle)
    head :ok
  end
end
