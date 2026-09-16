class ApplicationController < ActionController::Base
  # 存在しないレコード・他ユーザーのレコードへアクセスした場合、素の 404 ページを見せずに
  # フラッシュ付きで安全な画面へ戻す
  rescue_from ActiveRecord::RecordNotFound, with: :redirect_to_not_found

  before_action :authenticate_user! # 全体に適用
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :touch_guest_activity
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

  # ゲストの最終アクセス時刻を記録する。GuestUserPurger の削除判定にのみ使うため、
  # 削除対象ではない実ユーザーでは更新しない（読まれない値のために毎リクエスト
  # UPDATE を走らせないため）。
  #
  # 毎回書くと Neon への書き込みが増えるので 10 分に 1 回までに間引く。この間引き幅の
  # ぶんだけ値が古くなりうるので、削除の猶予（1 時間）はそれを見込んで設定している。
  #
  # updated_at を動かさず、バリデーションもコールバックも走らせないため update_column を使う。
  def touch_guest_activity
    return unless current_user&.guest?
    return if current_user.last_request_at&.after?(10.minutes.ago)

    current_user.update_column(:last_request_at, Time.current)
  end

  # ゲストに許可しない操作の共通ガード。UI 側でもリンクを出さないが、ルートは残るので
  # サーバ側でも必ず塞ぐ。
  #
  # status: :see_other は redirect_to_not_found に合わせている（DELETE / PATCH からの
  # 遷移で Turbo がリクエストメソッドを引き継がないようにするため）。
  def reject_guest
    return unless current_user&.guest?

    redirect_to mypage_path,
                alert: t("defaults.flash_message.guest_not_allowed"),
                status: :see_other
  end

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
