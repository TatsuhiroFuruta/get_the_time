# frozen_string_literal: true

# ゲストログイン。訪問者ごとに使い捨ての User を発行する。
#
# 本番に Solid Queue のワーカーが常駐していないため、古いゲストの削除は定期ジョブ
# ではなくこのリクエストの中で行う。ゲストを増やす経路と減らす経路が同一なので、
# 増加と削除が自動的に釣り合う。
class Users::GuestSessionsController < ApplicationController
  skip_before_action :authenticate_user!

  # ボタン連打によるアカウント量産を防ぐ。RegretSummariesController で既に
  # rate_limit を使っているので、同じ流儀に揃える。
  rate_limit to: 5, within: 1.hour,
             by: -> { request.remote_ip },
             with: -> { redirect_to root_path, alert: t("users.guest_sessions.flash_message.rate_limited") },
             only: :create

  def create
    purge_expired_guests
    user = GuestUserBuilder.call
    sign_in(user)
    # 時間切れで削除されたあとに「何が起きたか」を説明するための印。
    # sign_in の後に置く。
    session[:guest_sign_in] = true

    redirect_to mypage_path, notice: t("users.guest_sessions.flash_message.signed_in")
  end

  private

  # 掃除が失敗してもログインは通す。閲覧者にとってはデモが見られることが主目的で、
  # 掃除は次の訪問者が来たときにやり直せる。ただし握りつぶさずログには残す。
  def purge_expired_guests
    GuestUserPurger.call(except_id: current_user&.id)
  rescue StandardError => e
    Rails.logger.error("[GuestUserPurger] #{e.class}: #{e.message}")
  end
end
