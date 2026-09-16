# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  # GET /resource/sign_in
  def new
    # ゲストのセッションが張られていたのにユーザーが居ない = 利用時間切れで削除された後。
    # Devise の既定文言（ログインもしくはアカウント登録してください）では理由が伝わらない
    # ため、ゲスト向けの説明に差し替える。
    #
    # カスタムの FailureApp は作らない。認証失敗を全面的に差し替えることになり
    # 影響範囲が広すぎる。
    flash.now[:alert] = t("users.sessions.flash_message.guest_expired") if session.delete(:guest_sign_in)
    super
  end

  # DELETE /resource/sign_out
  def destroy
    # sign_out 後は current_user が nil になり、after_sign_out_path_for には
    # スコープ（:user）しか渡ってこない。判定はここで控えておく。
    @signing_out_guest = current_user&.guest?
    super
  end

  protected

  # ゲストはデモを終えた閲覧者なので、ログイン画面ではなくトップページへ戻す。
  def after_sign_out_path_for(resource_or_scope)
    @signing_out_guest ? root_path : super
  end
end
