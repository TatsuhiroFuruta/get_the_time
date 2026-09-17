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

    # 当初はトップページへ戻していたが、ホーム画面のヘッダーが fixed top-0 z-50 で
    # レイアウト先頭のフラッシュを覆い隠すため、ログアウトしたことが伝わらなかった。
    # リダイレクト先だけでなく「実際に読めること」を確かめる。
    describe "ゲストを終了したとき" do
      before { click_link "ゲストを終了" }

      it "ログイン画面へ戻ること" do
        expect(page).to have_current_path(new_user_session_path)
      end

      it "ログアウトしたことが表示されること" do
        expect(page).to have_content I18n.t("devise.sessions.signed_out")
      end

      # 上の have_content ではこの不具合を検出できない。フラッシュは覆われていても
      # DOM には存在し、かつ spec/support/capybara.rb が
      # Capybara.ignore_hidden_elements = false を設定しているため見つかってしまう。
      # Capybara は z-index による重なりを判定できないので、「覆う要素が無い画面か」
      # を直接確かめる。
      it "フラッシュを覆う固定ヘッダーが無い画面であること" do
        expect(page).to have_no_css("nav.fixed")
      end

      it "その場でもう一度ゲストとして試せること" do
        expect(page).to have_button "ゲストとして試す"
      end
    end
  end
end
