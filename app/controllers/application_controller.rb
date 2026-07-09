class ApplicationController < ActionController::Base
  # 存在しないレコード・他ユーザーのレコードへアクセスした場合、素の 404 ページを見せずに
  # フラッシュ付きで安全な画面へ戻す
  rescue_from ActiveRecord::RecordNotFound, with: :redirect_to_not_found

  before_action :authenticate_user! # 全体に適用
  before_action :configure_permitted_parameters, if: :devise_controller?
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  protected

  # 「ログアウトしました。」のフラッシュメッセージ表示できたことを確認済み
  def after_sign_out_path_for(resource_or_scope)
    new_user_session_path  # ログインページにリダイレクト
  end

  def configure_permitted_parameters
    # 名前・利用規約等への同意（agreement）を新規登録時に受け取る
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name, :agreement ])
    # 名前をアカウント編集で更新する場合に必要
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  private

  # DELETE / PATCH からの遷移で Turbo がリクエストメソッドを引き継がないよう 303 を返す
  def redirect_to_not_found
    redirect_to not_found_redirect_path,
                alert: t("defaults.flash_message.record_not_found"),
                status: :see_other
  end

  # 戻り先はコントローラごとに上書きする
  def not_found_redirect_path
    mypage_path
  end
end
