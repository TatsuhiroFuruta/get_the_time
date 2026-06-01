require "rails_helper"

RSpec.describe "StaticPages", type: :system do
  # =========================================================
  # ホーム画面
  # =========================================================
  describe "ホーム画面" do
    context "未ログインのとき" do
      it "ホーム画面が表示され、主要な動線リンクが見えること" do
        visit root_path

        aggregate_failures do
          expect(page).to have_content("Get The Time")
          expect(page).to have_link("はじめる", href: new_user_registration_path)
          expect(page).to have_link("ログイン", href: new_user_session_path)
        end
      end
    end

    context "ログイン済みのとき" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "root にアクセスするとマイページの内容が表示されること" do
        visit root_path

        aggregate_failures do
          expect(page).to have_content(user.name)
          expect(page).to have_link("使い方", href: how_to_use_path)
          expect(page).to have_link("ログアウト")
        end
      end
    end
  end

  # =========================================================
  # 使い方ページ
  # =========================================================
  describe "使い方ページ" do
    context "未ログインのとき" do
      it "ログインページへリダイレクトされること" do
        visit how_to_use_path
        expect(page).to have_current_path(new_user_session_path)
      end
    end

    context "ログイン済みのとき" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "表示され、マイページへ戻るリンクが見えること" do
        visit how_to_use_path

        aggregate_failures do
          expect(page).to have_current_path(how_to_use_path)
          expect(page).to have_content("概要")
          expect(page).to have_link("マイページに戻る", href: mypage_path)
        end
      end
    end
  end

  # =========================================================
  # 振り返り方ページ
  # =========================================================
  describe "振り返り方ページ" do
    context "未ログインのとき" do
      it "ログインページへリダイレクトされること" do
        visit reflection_guide_path
        expect(page).to have_current_path(new_user_session_path)
      end
    end

    context "ログイン済みのとき" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "表示され、各評価項目とマイステータスへ戻るリンクが見えること" do
        visit reflection_guide_path

        aggregate_failures do
          expect(page).to have_current_path(reflection_guide_path)
          expect(page).to have_content("振り返り方")
          expect(page).to have_content("満足度")
          expect(page).to have_content("進行度")
          expect(page).to have_content("作業の質")
          expect(page).to have_content("集中度")
          expect(page).to have_content("疲労感")
          expect(page).to have_link("← マイステータスに戻る", href: mystatus_path)
        end
      end

      it "マイステータスに戻るリンクからマイステータスへ遷移できること" do
        visit reflection_guide_path
        click_link "← マイステータスに戻る"

        expect(page).to have_current_path(mystatus_path)
      end
    end
  end
end
