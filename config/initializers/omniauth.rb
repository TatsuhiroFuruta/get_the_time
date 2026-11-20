# OmniAuth の偽装ホスト対策（GHSA-m27g-v28p-f9fx / CVE-2026-63183、omniauth 2.2.0 で追加）。
#
# OmniAuth は Google に渡すコールバック URL（redirect_uri）を、リクエストの Host /
# X-Forwarded-Host ヘッダーから組み立てる。これらは偽装できるため、許可したホスト以外では
# 認証を中断させる（invalid_host で失敗し、Users::OmniauthCallbacksController#failure へ）。
# 設定しないと防御は有効にならず、ログイン操作のたびに警告ログが出る。
#
# ドメインの一覧は config/environments/production.rb の config.hosts を正本として流用する。
# - 本番だけで設定する: 開発の config.hosts には IPAddr などが入るが、allowed_hosts は
#   文字列（ホスト全体と大文字小文字を無視して一致）か正規表現しか受け付けない
# - config.hosts に Rails 流のサブドメイン指定（".get-the-time.com" のような先頭ドット）や
#   IPAddr を足すと、OmniAuth ではそのホストと一致しなくなり、そのドメインからの Google ログインが
#   失敗する。足す場合はここで正規表現に変換すること
# - full_host は使わない: 1 つのドメインに固定すると、www や onrender.com からログインしたとき
#   コールバックが別ドメインに飛び、セッションが切れる
if Rails.env.production?
  OmniAuth.config.allowed_hosts = Rails.application.config.hosts
end
