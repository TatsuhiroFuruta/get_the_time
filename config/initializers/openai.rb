# OpenAI クライアント（ruby-openai）の初期化
# API キーは credentials（config/credentials.yml.enc）の openai.api_key を参照する。
# テスト/CI ではキー未設定でもよい（RegretSummarizer をスタブし実呼び出ししないため）。
OpenAI.configure do |config|
  config.access_token = Rails.application.credentials.dig(:openai, :api_key)
end
