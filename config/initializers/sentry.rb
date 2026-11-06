# 本番のエラーを Sentry へ送る。送信は SDK 内のスレッドで行うので Active Job に依存しない
# （本番は Solid Queue のワーカーが動いていない）。
#
# 活動記録などには内面に関する機微な情報が含まれるため、送る内容は最小限に絞る
# （プライバシーポリシー第6条に記載）。設定を緩める場合はポリシーも見直すこと。
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  # 開発環境・テストのエラーで無料枠（月 5,000 件）を消費しないようにする
  config.enabled_environments = %w[production]
  # どのデプロイからエラーが出始めたかを追えるようにする（Render が自動で設定する）
  config.release = ENV["RENDER_GIT_COMMIT"]

  # SQL やログの内容を送らない
  config.breadcrumbs_logger = []

  data_collection = config.data_collection
  # IP アドレスを送らない。ユーザー ID は ApplicationController で明示的に渡す
  data_collection.user_info = false
  data_collection.cookies = false
  # 活動記録のコメントなどを送らない
  data_collection.http_bodies = []
  # 検索語を送らない
  data_collection.url_query_params = false
  data_collection.database_query_data = false
  # Referer には検索語入りの URL が入るので、初期設定の拒否リストでは防げない。
  # 許可リストにして、ブラウザや OS の把握に必要な User-Agent だけを残す
  data_collection.http_headers.request.mode = :allow_list
  data_collection.http_headers.request.terms = %w[user-agent]

  # PostgreSQL のエラーメッセージには行の内容やメールアドレスがそのまま入り、上の設定では
  # 防げない。別の例外に包まれていても消えるよう cause もたどる。例外のクラス名と
  # スタックトレースは残るので、原因の調査はできる。
  config.before_send = lambda do |event, hint|
    # capture_message のイベントには例外がないので、伏せるものがない
    next event unless event.exception

    # 元の例外が hint にないイベントは、ここで NoMethodError になり送られない。種類を
    # 確かめられないものを送らないための動作なので、nil を許容する形に変えないこと。
    exceptions = Sentry::Utils::ExceptionCauseChain.exception_to_array(hint[:exception])
    if exceptions.any? { |exception| exception.is_a?(ActiveRecord::StatementInvalid) || exception.is_a?(PG::Error) }
      event.exception.values.each { |value| value.value = "[Filtered]" }
    end
    event
  end
end
