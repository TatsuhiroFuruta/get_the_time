require "rails_helper"

RSpec.describe "Account", type: :system do
  let(:user) { create(:user, name: "元の名前", email: "original@example.com", password: "password123", password_confirmation: "password123") }
  # マイページ右上のユーザー名カード（導線）は dark_time と light_time の両方がある時のみ表示される
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before do
    sign_in user
  end

  describe "アカウント情報画面への導線" do
    it "ハンバーガーメニューの「アカウント情報」からアカウント情報画面へ遷移する" do
      visit mypage_path

      find('[data-hamburger-target="button"]').click
      within('[data-hamburger-target="menu"]') do
        click_on "アカウント情報"
      end

      aggregate_failures do
        expect(page).to have_current_path(user_account_path)
        expect(page).to have_content("元の名前")
        expect(page).to have_content("original@example.com")
      end
    end
  end

  describe "アカウント情報表示" do
    it "名前とメールアドレスが表示される" do
      visit user_account_path

      aggregate_failures do
        expect(page).to have_content("元の名前")
        expect(page).to have_content("original@example.com")
        expect(page).to have_link("編集する")
      end
    end

    it "マイページへ戻れる" do
      visit user_account_path

      click_link "← マイページに戻る"

      expect(page).to have_current_path(mypage_path)
    end
  end

  describe "光・闇いずれかが未登録の場合のハンバーガーメニュー" do
    # 光・闇の時間を持たないユーザーでログインし直す
    let(:incomplete_user) { create(:user) }

    before do
      sign_out user
      sign_in incomplete_user
      visit mypage_path
      find('[data-hamburger-target="button"]').click
    end

    it "マイページとアカウント情報のみ表示される" do
      within('[data-hamburger-target="menu"]') do
        aggregate_failures do
          expect(page).to have_link("マイページ")
          expect(page).to have_link("アカウント情報")
          expect(page).not_to have_link("活動記録")
          expect(page).not_to have_link("マイステータス")
          expect(page).not_to have_link("後悔した1日の記録一覧")
        end
      end
    end

    it "アカウント情報へ遷移できる" do
      within('[data-hamburger-target="menu"]') do
        click_on "アカウント情報"
      end

      expect(page).to have_current_path(user_account_path)
    end
  end

  describe "光・闇の両方が登録済みの場合のハンバーガーメニュー" do
    before do
      visit mypage_path
      find('[data-hamburger-target="button"]').click
    end

    it "全メニュー項目とアカウント情報が表示される" do
      within('[data-hamburger-target="menu"]') do
        aggregate_failures do
          expect(page).to have_link("マイページ")
          expect(page).to have_link("活動記録")
          expect(page).to have_link("マイステータス")
          expect(page).to have_link("後悔した1日の記録一覧")
          expect(page).to have_link("アカウント情報")
        end
      end
    end
  end

  describe "未ログインの場合" do
    it "アカウント情報画面はログイン画面にリダイレクトされる" do
      sign_out user
      visit user_account_path

      expect(page).to have_current_path(new_user_session_path)
    end
  end

  describe "アカウント編集" do
    context "正常系" do
      it "現在のパスワードを入力して名前を更新するとアカウント情報画面へ遷移し、更新される" do
        visit user_account_path
        click_link "編集する"

        expect(page).to have_current_path(edit_user_registration_path)

        fill_in "名前", with: "新しい名前"
        fill_in "現在のパスワード", with: "password123"
        click_button "更新する"

        aggregate_failures do
          expect(page).to have_current_path(user_account_path)
          expect(page).to have_content(I18n.t("devise.registrations.updated"))
          expect(page).to have_content("新しい名前")
          expect(user.reload.name).to eq("新しい名前")
        end
      end

      it "現在のパスワードを入力してメールアドレスを更新できる" do
        visit edit_user_registration_path

        fill_in "メールアドレス", with: "updated@example.com"
        fill_in "現在のパスワード", with: "password123"
        click_button "更新する"

        aggregate_failures do
          expect(page).to have_current_path(user_account_path)
          expect(page).to have_content("updated@example.com")
          expect(user.reload.email).to eq("updated@example.com")
        end
      end

      it "現在のパスワードを入力して新しいパスワードに変更できる" do
        visit edit_user_registration_path

        fill_in "パスワード", with: "newpassword123", exact: true
        fill_in "パスワード確認", with: "newpassword123"
        fill_in "現在のパスワード", with: "password123"
        click_button "更新する"

        aggregate_failures do
          expect(page).to have_current_path(user_account_path)
          expect(user.reload.valid_password?("newpassword123")).to be true
        end
      end

      it "キャンセルするとアカウント情報画面へ戻る" do
        visit edit_user_registration_path

        click_link "キャンセル"

        expect(page).to have_current_path(user_account_path)
      end
    end

    context "異常系" do
      it "現在のパスワードが未入力の場合は更新できない" do
        visit edit_user_registration_path

        fill_in "名前", with: "新しい名前"
        # 現在のパスワードを入力しない
        click_button "更新する"

        aggregate_failures do
          expect(page).to have_current_path(edit_user_registration_path)
          expect(page).to have_content("現在のパスワードを入力してください")
          expect(user.reload.name).to eq("元の名前")
        end
      end

      it "現在のパスワードが誤っている場合は更新できない" do
        visit edit_user_registration_path

        fill_in "名前", with: "新しい名前"
        fill_in "現在のパスワード", with: "wrongpassword"
        click_button "更新する"

        aggregate_failures do
          expect(page).to have_current_path(edit_user_registration_path)
          expect(page).to have_content("現在のパスワードは不正な値です")
          expect(user.reload.name).to eq("元の名前")
        end
      end

      it "名前を空にすると更新できない" do
        visit edit_user_registration_path

        fill_in "名前", with: ""
        fill_in "現在のパスワード", with: "password123"
        click_button "更新する"

        aggregate_failures do
          expect(page).to have_current_path(edit_user_registration_path)
          expect(page).to have_content("名前を入力してください")
          expect(user.reload.name).to eq("元の名前")
        end
      end
    end
  end
end
