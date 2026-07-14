require "rails_helper"

RSpec.describe "タイマーの排他制御", type: :system do
  let(:user) { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time) { create(:dark_time, user: user) }
  let!(:pomodoro_setting) { user.pomodoro_setting }

  before { sign_in user }

  # =========================================================
  # ガード A: 浄化タイマー計測中 → ポモドーロ画面に入れない（サーバ側）
  # =========================================================
  describe "浄化タイマーの計測中" do
    let!(:purification_time) { create(:purification_time, :running, user: user) }

    it "ポモドーロ画面を開こうとするとマイページへ追い返されること" do
      visit pomodoro_timer_activity_records_path

      aggregate_failures do
        expect(page).to have_current_path(mypage_path)
        expect(page).to have_content("浄化タイマーの実行中はポモドーロタイマーを開始できません")
      end
    end
  end

  # =========================================================
  # ガード B: 光の時間の活動中 → 浄化タイマー画面に入れない（クライアント側リース）
  # =========================================================
  describe "ポモドーロの計測中" do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    it "別タブで浄化タイマー画面を開こうとするとマイページへ追い返されること" do
      visit pomodoro_timer_activity_records_path
      click_button "スタート"

      # リースが書き込まれるのを待つ
      expect(page).to have_css("[data-pomodoro-target='startButton'].hidden", visible: :all)

      new_window = open_new_window
      within_window new_window do
        visit purification_time_path

        aggregate_failures do
          expect(page).to have_current_path(mypage_path, ignore_query: true)
          expect(page).to have_content("別のタブで光の時間の活動を実行中です")
        end
      end
    end

    it "別タブでポモドーロ画面を開こうとしてもマイページへ追い返されること（光の時間の活動は 1 つだけ）" do
      visit pomodoro_timer_activity_records_path
      click_button "スタート"
      expect(page).to have_css("[data-pomodoro-target='startButton'].hidden", visible: :all)

      new_window = open_new_window
      within_window new_window do
        visit pomodoro_timer_activity_records_path
        expect(page).to have_current_path(mypage_path, ignore_query: true)
      end
    end
  end

  describe "ポモドーロを開始していないとき" do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    it "タイマー画面を開いているだけでは浄化タイマーをブロックしないこと" do
      visit pomodoro_timer_activity_records_path

      new_window = open_new_window
      within_window new_window do
        visit purification_time_path
        expect(page).to have_current_path(purification_time_path)
      end
    end
  end
end
