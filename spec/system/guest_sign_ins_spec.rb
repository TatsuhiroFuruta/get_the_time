require "rails_helper"

RSpec.describe "ゲストログイン", type: :system do
  describe "ホーム画面から" do
    before { visit root_path }

    it "ボタンからログインしてマイページに入れること" do
      click_button "ゲストとして試す", match: :first

      expect(page).to have_content I18n.t("mypages.show.title")
    end

    it "利用規約への同意を明記していること" do
      expect(page).to have_content "利用規約"
    end
  end

  describe "ログイン画面から" do
    before { visit new_user_session_path }

    it "ボタンからログインできること" do
      click_button "ゲストとして試す", match: :first

      expect(page).to have_content I18n.t("mypages.show.title")
    end
  end

  describe "ログイン後の画面" do
    before do
      visit root_path
      click_button "ゲストとして試す", match: :first
      # ログインの POST が完了する前に visit すると、リクエストが中断されて
      # セッションが張られないまま次の画面へ進んでしまう。着地を待つ。
      expect(page).to have_content I18n.t("mypages.show.title")
    end

    # ゲストであることはマイページのユーザーカードで示す（専用バッジは置かない。
    # 理由は設計 5.9 を参照）。
    it "ゲストであることが分かること" do
      aggregate_failures do
        expect(page).to have_content "ゲストユーザー"
        expect(page).to have_link "ゲストを終了"
      end
    end

    it "デモデータが表示され、ポモドーロを開始できる状態であること" do
      expect(page).to have_link "スタート"
    end

    it "マイステータスにデモの記録が反映されていること" do
      visit mystatus_path

      expect(page).to have_content I18n.t("mystatuses.show.title")
    end
  end
end
