require "rails_helper"

RSpec.describe "GoogleAuthentications", type: :system do
  it "ログイン画面と新規登録画面に Google 認証ボタンが表示される" do
    visit new_user_session_path
    expect(page).to have_button("Google で続行")

    visit new_user_registration_path
    expect(page).to have_button("Google で続行")
  end

  it "Google 認証で新規登録・ログインできる" do
    mock_google_oauth2(email: "google_user@example.com", name: "グーグル太郎")

    visit new_user_session_path
    click_button "Google で続行"

    aggregate_failures do
      expect(page).to have_current_path(root_path)
      # 成功フラッシュがレイアウトに描画されていること
      expect(page).to have_content(
        I18n.t("devise.omniauth_callbacks.success", kind: "Google")
      )
      expect(page).to have_content("グーグル太郎")
      expect(page).to have_link("ログアウト")
      expect(User.find_by(email: "google_user@example.com").provider).to eq("google_oauth2")
    end
  end
end
