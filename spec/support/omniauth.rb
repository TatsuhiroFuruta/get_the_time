# OmniAuth（Google）認証のテスト用ヘルパー。
# test_mode を有効にし、各テストで mock_auth を組み立てられるようにする。
OmniAuth.config.test_mode = true

module OmniauthHelpers
  # Google 認証成功時のモックを設定する
  def mock_google_oauth2(email:, name: "テスト太郎", uid: "123456789")
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name }
    )
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    # System Spec / Request Spec のミドルウェア経由でも参照できるようにする
    Rails.application.env_config["omniauth.auth"] = auth
    auth
  end

  # Google 認証失敗時のモックを設定する
  def mock_google_oauth2_failure
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    Rails.application.env_config["omniauth.auth"] = nil
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers

  # テスト間でモックが漏れないようにリセットする
  config.after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete("omniauth.auth")
  end
end
