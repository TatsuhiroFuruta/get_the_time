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

  # ゲストのログアウトも通常どおりログイン画面へ戻す（遷移先を分けない）。
  # 当初はトップページへ戻していたが、ホーム画面のヘッダーが fixed top-0 z-50 で
  # レイアウト先頭のフラッシュを覆い隠すため、「ログアウトしました。」が見えなかった。
  # ログイン画面には「ゲストとして試す」ボタンがあるので、やり直しの導線も保たれる。
end
