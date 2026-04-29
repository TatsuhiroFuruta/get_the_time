class StaticPagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:home]
  def home; end

  def how_to_use; end
end
