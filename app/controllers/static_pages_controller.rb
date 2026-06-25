class StaticPagesController < ApplicationController
  # 利用規約・プライバシーポリシーは未ログインユーザー（登録前の閲覧者）も参照できる
  skip_before_action :authenticate_user!, only: [ :home, :terms, :privacy ]
  def home; end

  def how_to_use; end

  def reflection_guide; end

  def terms; end

  def privacy; end
end
