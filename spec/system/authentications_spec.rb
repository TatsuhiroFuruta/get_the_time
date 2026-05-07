require 'rails_helper'

RSpec.describe "Authentications", type: :system do
  let!(:user) { create(:user) }

  it "新規登録できる" do
    visit new_user_registration_path

    fill_in "名前", with: "山田太郎"
    fill_in "メールアドレス", with: "new@example.com"
    fill_in "パスワード", with: "password123"
    fill_in "パスワード確認", with: "password123"
    click_button "アカウント作成"

    expect(page).to have_current_path(root_path)
    expect(page).to have_content(
      I18n.t("devise.registrations.signed_up")
    )
  end

  it "新規登録に失敗するとエラーメッセージが表示される" do
    visit new_user_registration_path

    fill_in "名前", with: "山田太郎"
    fill_in "メールアドレス", with: ""
    fill_in "パスワード", with: "password123"
    fill_in "パスワード確認", with: "password123"
    click_button "アカウント作成"

    expect(page).to have_current_path(new_user_registration_path)

    # エラーメッセージ
    expect(page).to have_content("メールアドレスを入力してください")
    # 入力した値が保持されているか
    expect(page).to have_field("名前", with: "山田太郎")
    expect(page).to have_field("メールアドレス", with: "")
  end

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
