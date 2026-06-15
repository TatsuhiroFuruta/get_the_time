# Resend（メール送信）クライアントの初期化
# API キーは credentials（config/credentials.yml.enc）の resend.api_key を参照する。
# 開発は letter_opener_web、テストは :test 配信のためキー未設定でもよい。
Resend.api_key = Rails.application.credentials.dig(:resend, :api_key)
