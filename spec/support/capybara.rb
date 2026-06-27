require "capybara/rspec"
require "selenium-webdriver"

# CI の高負荷時、Turbo Drive の遷移＋描画がデフォルトの待機（2秒）を超えて
# システムスペックが間欠的に落ちることがあるため、待機時間を延長する。
# 待機を延ばすだけなのでパスするテストには影響せず、本物の失敗もタイムアウト後に検出される。
# 5秒でも main マージ後 CI で間欠失敗(#218)したため 10秒へ引き上げ。
Capybara.default_max_wait_time = 10

# Docker開発環境用(リモートChromeコンテナを使用)
Capybara.register_driver :remote_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("no-sandbox")
  options.add_argument("headless")
  options.add_argument("disable-gpu")
  options.add_argument("window-size=1680,1050")
  Capybara::Selenium::Driver.new(
    app,
    browser: :remote,
    url: ENV["SELENIUM_DRIVER_URL"],
    capabilities: options
  )
end

# CI環境/ローカル直接実行用(ホストのHeadless Chromeを使用)
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--window-size=1680,1050")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    if ENV["SELENIUM_DRIVER_URL"].present?
      # Docker環境: リモートChromeコンテナを使用
      driven_by :remote_chrome
      Capybara.server_host = IPSocket.getaddress(Socket.gethostname)
      Capybara.server_port = 4444
      Capybara.app_host = "http://#{Capybara.server_host}:#{Capybara.server_port}"
    else
      # CI/ローカル直接実行: ホストのHeadless Chromeを使用
      driven_by :headless_chrome
    end
    Capybara.ignore_hidden_elements = false
  end
end
