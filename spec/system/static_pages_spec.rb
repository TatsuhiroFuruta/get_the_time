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

  # =========================================================
  # 利用規約・プライバシーポリシー
  # =========================================================
  describe "利用規約・プライバシーポリシー" do
    context "未ログインのとき" do
      it "ホーム画面のフッターリンクから利用規約ページへ遷移できること" do
        visit root_path
        click_link "利用規約"

        aggregate_failures do
          expect(page).to have_current_path(terms_path)
          expect(page).to have_content("第6条（禁止事項）")
        end
      end

      it "ホーム画面のフッターリンクからプライバシーポリシーページへ遷移できること" do
        visit root_path
        click_link "プライバシーポリシー"

        aggregate_failures do
          expect(page).to have_current_path(privacy_path)
          expect(page).to have_content("第6条（外部サービスへの取り扱いの委託）")
        end
      end

      it "未ログインでも利用規約ページが直接開けること" do
        visit terms_path

        aggregate_failures do
          expect(page).to have_current_path(terms_path)
          expect(page).to have_content("利用規約")
          expect(page).to have_link("← トップに戻る", href: root_path)
        end
      end

      it "未ログインでもプライバシーポリシーページが直接開けること" do
        visit privacy_path

        aggregate_failures do
          expect(page).to have_current_path(privacy_path)
          expect(page).to have_content("プライバシーポリシー")
          expect(page).to have_link("← トップに戻る", href: root_path)
        end
      end
    end

    context "ログイン済みのとき（ハンバーガーメニュー）" do
      let(:user) { create(:user) }
      let!(:light_time) { create(:light_time, :current, user: user) }
      let!(:dark_time)  { create(:dark_time, user: user) }

      before do
        sign_in user
        visit mypage_path
      end

      it "メニューから利用規約ページへ遷移できること" do
        find('[data-hamburger-target="button"]').click
        within('[data-hamburger-target="menu"]') do
          click_on "利用規約"
        end

        expect(page).to have_current_path(terms_path)
      end

      it "メニューからプライバシーポリシーページへ遷移できること" do
        find('[data-hamburger-target="button"]').click
        within('[data-hamburger-target="menu"]') do
          click_on "プライバシーポリシー"
        end

        expect(page).to have_current_path(privacy_path)
      end
    end
  end
end
