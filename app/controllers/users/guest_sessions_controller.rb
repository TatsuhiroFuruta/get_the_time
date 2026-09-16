# frozen_string_literal: true

# ゲストログイン。訪問者ごとに使い捨ての User を発行する。
#
# 本番に Solid Queue のワーカーが常駐していないため、古いゲストの削除は定期ジョブ
# ではなくこのリクエストの中で行う。ゲストを増やす経路と減らす経路が同一なので、
# 増加と削除が自動的に釣り合う。
class Users::GuestSessionsController < ApplicationController
  # heartbeat はログイン中のゲストからしか来ないので認証を外さない。
  skip_before_action :authenticate_user!, only: :create

  # ログイン済みの人にはゲストを発行しない。sign_in は Warden のユーザーを無条件に
  # 差し替えるため、別タブでログインしたあとにこの画面へ戻って押す、bfcache から
  # 復元された古いトップページで押す、といった経路で、本アカウントから使い捨ての
  # ゲストへ黙って入れ替わってしまう。すでにゲストの場合も、既存のデモを捨てて
  # 作り直す意味がない。
  before_action :redirect_if_signed_in, only: :create

  # ボタン連打によるアカウント量産を防ぐ。RegretSummariesController で既に
  # rate_limit を使っているので、同じ流儀に揃える。
  #
  # 数える単位は IP なので、1人あたりの回数ではなく「同じ回線の向こうにいる人数」で
  # 上限を決める必要がある。同じ会社や学校の NAT 配下からは全員で1枠を共有するため、
  # 5 にすると6人目が一度も押していないのにデモを見られない。閲覧者が同じオフィスから
  # 複数人で見る状況はポートフォリオでは普通に起きるので、20 にしている。
  # 自動化された場合でも 1 IP あたり 20 件/時間（約 320KB）に収まる。
  MAX_SIGN_INS_PER_HOUR = 20

  rate_limit to: MAX_SIGN_INS_PER_HOUR, within: 1.hour,
             by: -> { rate_limit_key },
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

  # ゲストが「まだ見ている」ことをサーバへ伝えるだけの空のアクション。
  #
  # ポモドーロと浄化タイマーの計測はすべてクライアント側で完結しており、計測中は
  # サーバへのリクエストが一切発生しない（30秒ごとの heartbeat も localStorage を
  # 書くだけ）。そのままでは last_request_at が更新されず、計測中のゲストが
  # GuestUserPurger の削除対象に入ってしまう。
  #
  # 実際の更新は ApplicationController#touch_guest_activity が担い、10分に間引かれる。
  # したがってこの ping の間隔を短くしても DB への書き込みは増えない。
  def heartbeat
    head :no_content
  end

  private

  def redirect_if_signed_in
    redirect_to mypage_path if user_signed_in?
  end

  # レート制限を数える単位。
  #
  # request.remote_ip は使えない。本番は Cloudflare が前段にいるため
  # X-Forwarded-For が [実クライアント, Cloudflare, Render内部] となり、Rails の
  # RemoteIp は右端の非プライベート IP を採るので Cloudflare のエッジ IP になる。
  # エッジ IP は訪問者ごとではなく地域ごとなので、同じ地域の訪問者が全員ひとつの枠を
  # 共有してしまい、20 回/時間が事実上の全体上限として効く。
  #
  # CF-Connecting-IP は Cloudflare が付ける実クライアント IP。クライアントが送って
  # きた同名ヘッダは Cloudflare が上書きするため、Cloudflare を通る限り偽装できない。
  #
  # trusted_proxies に Cloudflare の IP 範囲を設定する手もあるが、範囲の一覧を自前で
  # 持ち続けることになり、Cloudflare 側の変更で静かに壊れるため採らない。
  #
  # 既知の限界: Render のオリジンへ直接アクセスできる場合、Cloudflare を迂回して
  # このヘッダを自分で付けられる。ただし対処前は枠が全員共有で何も守れていなかった
  # ため悪化はしない。レート制限はセキュリティ境界ではなく濫用の緩和と位置づける。
  def rate_limit_key
    request.headers["CF-Connecting-IP"].presence || request.remote_ip
  end

  # 掃除が失敗してもログインは通す。閲覧者にとってはデモが見られることが主目的で、
  # 掃除は次の訪問者が来たときにやり直せる。ただし握りつぶさずログには残す。
  def purge_expired_guests
    GuestUserPurger.call(except_id: current_user&.id)
  rescue StandardError => e
    # ここが失敗を知る唯一の経路なので、バックトレースまで残す。
    Rails.logger.error("[GuestUserPurger] #{e.full_message(highlight: false)}")
  end
end
