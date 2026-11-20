require "rails_helper"

# OmniAuth 2.2.0 の偽装ホスト対策（GHSA-m27g-v28p-f9fx）。
# 本番では config/initializers/omniauth.rb で allowed_hosts を設定している。
RSpec.describe "OmniAuth の allowed_hosts", type: :request do
  describe "POST /users/auth/google_oauth2（認証の開始）" do
    # テストモードでは OmniAuth がホストの判定を飛ばすため、一時的に切って実際の経路を通す。
    # 他の spec に影響しないよう、設定は必ず元に戻す。
    around do |example|
      original_test_mode = OmniAuth.config.test_mode
      original_allowed_hosts = OmniAuth.config.allowed_hosts
      OmniAuth.config.test_mode = false
      OmniAuth.config.allowed_hosts = [ "get-the-time.com" ]
      example.run
    ensure
      OmniAuth.config.test_mode = original_test_mode
      OmniAuth.config.allowed_hosts = original_allowed_hosts
    end

    it "許可したホストでは、そのホストのコールバック URL で Google の認可画面へリダイレクトする" do
      host! "get-the-time.com"

      post user_google_oauth2_omniauth_authorize_path

      redirect_uri = Rack::Utils.parse_query(URI(response.location).query)["redirect_uri"]
      aggregate_failures do
        expect(response.location).to start_with("https://accounts.google.com/")
        expect(redirect_uri).to eq("http://get-the-time.com/users/auth/google_oauth2/callback")
      end
    end

    it "許可していないホストでは、Google へ進まず認証を中断してトップへ戻す" do
      host! "evil.example.com"

      post user_google_oauth2_omniauth_authorize_path

      aggregate_failures do
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Google認証に失敗しました。")
        expect(response.location).not_to include("accounts.google.com")
      end
    end
  end

  it "テスト環境では allowed_hosts を設定しない（本番だけで有効にする）" do
    expect(OmniAuth.config.allowed_hosts).to be_nil
  end
end
