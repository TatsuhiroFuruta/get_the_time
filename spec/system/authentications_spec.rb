require 'rails_helper'

RSpec.describe "Authentication", type: :system do
  let!(:user) { create(:user) }

  it "ログインできる" do
    visit new_user_session_path

    fill_in "メールアドレス", with: user.email
    fill_in "パスワード", with: "password123"
    click_button "ログイン"

    expect(page).to have_current_path(root_path)
    expect(page).to have_content(
      I18n.t("devise.sessions.signed_in")
    )
  end

  it "新規登録できる" do
    visit new_user_registration_path

    fill_in "名前", with: "new@example.com"
    fill_in "メールアドレス", with: "new@example.com"
    fill_in "パスワード", with: "password123"
    fill_in "パスワード確認", with: "password123"
    click_button "アカウント作成"

    expect(page).to have_current_path(root_path)
    expect(page).to have_content(
      I18n.t("devise.registrations.signed_up")
    )
  end

  it "ログアウトできる" do
    # ログイン状態を作る
    visit new_user_session_path

    fill_in "メールアドレス", with: user.email
    fill_in "パスワード", with: "password123"
    click_button "ログイン"

    # ログアウト操作
    click_link "ログアウト"

    expect(page).to have_current_path(new_user_session_path)
    expect(page).to have_content(
      I18n.t("devise.sessions.signed_out")
    )
  end

  it "未ログインでマイページにアクセスするとログイン画面に飛ばされる" do
    visit mypage_path

    expect(page).to have_current_path(new_user_session_path)
    expect(page).to have_content(
      I18n.t("devise.failure.unauthenticated")
    )
  end

end
