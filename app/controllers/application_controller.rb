class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  protected

  # 「ログアウトしました。」のフラッシュメッセージ表示できたことを確認済み
  def after_sign_out_path_for(resource_or_scope)
    new_user_session_path  # ログインページにリダイレクト
  end

  def configure_permitted_parameters
		# 名前を新規登録する場合に必要
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
  end
end
