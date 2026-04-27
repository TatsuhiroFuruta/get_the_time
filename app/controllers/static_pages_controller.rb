class StaticPagesController < ApplicationController
  skip_before_action :authenticate_user!
  def home; end

  def how_to_use; end
end
