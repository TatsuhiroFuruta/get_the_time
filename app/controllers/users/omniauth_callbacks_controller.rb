# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # GET|POST /users/auth/google_oauth2/callback
  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      # 保存に失敗した場合（バリデーションエラー等）は新規登録画面へ戻す
      session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
    end
  end

  # 認証がキャンセル・失敗したときの遷移先
  def failure
    redirect_to root_path, alert: "Google認証に失敗しました。"
  end
end
