require "rails_helper"

RSpec.describe "PasswordResets", type: :system do
  let!(:user) { create(:user) }

  it "ログイン画面の導線から再設定を申請できる" do
    visit new_user_session_path
    click_link "パスワードをお忘れですか？"
    expect(page).to have_current_path(new_user_password_path)

    fill_in "メールアドレス", with: user.email
    click_button "再設定用のメールを送信する"

    aggregate_failures do
      expect(page).to have_current_path(new_user_session_path)
      # paranoid モードのため、登録済み・未登録を問わず同一文言を表示する
      expect(page).to have_content(I18n.t("devise.passwords.send_paranoid_instructions"))
    end
  end

  it "再設定リンクから新しいパスワードを設定でき、変更後はログイン済みになる" do
    # メール内リンク相当の再設定トークンを発行する
    token = user.send_reset_password_instructions

    visit edit_user_password_path(reset_password_token: token)

    # exact: true で「新しいパスワード（確認）」と区別する
    fill_in "新しいパスワード", with: "newpassword123", exact: true
    fill_in "新しいパスワード（確認）", with: "newpassword123"
    click_button "パスワードを変更する"

    # 変更完了でログイン済みとなりトップへ遷移する（sign_in_after_reset_password）
    aggregate_failures do
      expect(page).to have_current_path(root_path)
      expect(page).to have_content(I18n.t("devise.passwords.updated"))
    end
  end

  it "確認用パスワードが一致しないとエラーになる" do
    token = user.send_reset_password_instructions

    visit edit_user_password_path(reset_password_token: token)

    fill_in "新しいパスワード", with: "newpassword123", exact: true
    fill_in "新しいパスワード（確認）", with: "different123"
    click_button "パスワードを変更する"

    expect(page).to have_content("パスワード（確認用）とパスワードの入力が一致しません")
  end

  it "申請画面でメールアドレスが空だと送信できない" do
    visit new_user_password_path

    fill_in "メールアドレス", with: ""
    click_button "再設定用のメールを送信する"

    # email_field の required により、ブラウザが送信をブロックして申請画面に留まる。
    # paranoid モードのためサーバ側は空でもリダイレクトしてしまうので、
    # 「空 → 入力を促す」UX はクライアント側のバリデーションで担保している。
    aggregate_failures do
      expect(page).to have_current_path(new_user_password_path)
      expect(page).to have_no_content(I18n.t("devise.passwords.send_paranoid_instructions"))
    end
  end
end
