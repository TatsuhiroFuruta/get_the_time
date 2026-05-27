require "rails_helper"

RSpec.describe "PomodoroSettings", type: :system do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "マイページのポモドーロ時間設定UI" do
    context "光の時間・闇の時間が両方未登録のとき" do
      it "設定ボタンが表示されないこと" do
        visit mypage_path
        expect(page).not_to have_button("⚙ ポモドーロ時間を設定")
      end
    end

    context "光の時間・闇の時間が両方登録済みのとき" do
      let!(:light_time) { create(:light_time, :current, user: user) }
      let!(:dark_time) { create(:dark_time, user: user) }

      it "設定ボタンが表示されること" do
        visit mypage_path
        expect(page).to have_button("⚙ ポモドーロ時間を設定")
      end

      context "モーダル表示", js: true do
        it "ボタンをクリックするとモーダルが開き、デフォルト値が表示されること" do
          visit mypage_path

          # 初期状態ではモーダルは非表示
          expect(page).to have_selector(
            '[data-pomodoro-setting-modal-target="modal"].hidden',
            visible: :all
          )

          click_on "⚙ ポモドーロ時間を設定"

          # モーダルが表示される
          expect(page).to have_selector(
            '[data-pomodoro-setting-modal-target="modal"]:not(.hidden)',
            wait: 5
          )

          # デフォルト値が表示される
          within('[data-pomodoro-setting-modal-target="modal"]') do
            aggregate_failures do
              expect(page).to have_field("活動時間", with: "25")
              expect(page).to have_field("休憩時間", with: "5")
            end
          end
        end

        it "「閉じる」をクリックするとモーダルが閉じること" do
          visit mypage_path
          click_on "⚙ ポモドーロ時間を設定"

          within('[data-pomodoro-setting-modal-target="modal"]') do
            click_on "閉じる"
          end

          expect(page).to have_selector(
            '[data-pomodoro-setting-modal-target="modal"].hidden',
            visible: :all,
            wait: 5
          )
        end
      end
    end
  end

  describe "ポモドーロ時間の更新フロー", js: true do
    let!(:light_time) { create(:light_time, :current, user: user) }
    let!(:dark_time) { create(:dark_time, user: user) }

    before do
      visit mypage_path
      click_on "⚙ ポモドーロ時間を設定"
    end

    context "正常系" do
      it "有効な値を入力して保存するとマイページに戻り、フラッシュが表示されること" do
        within('[data-pomodoro-setting-modal-target="modal"]') do
          fill_in "活動時間", with: 50
          fill_in "休憩時間", with: 10
          click_on "保存する"
        end

        # have_current_path がリダイレクト完了まで待機するため、reload はその後に行う
        expect(page).to have_current_path(mypage_path)

        user.pomodoro_setting.reload
        aggregate_failures do
          expect(page).to have_content(
            I18n.t("defaults.flash_message.updated", item: PomodoroSetting.model_name.human)
          )
          expect(user.pomodoro_setting.work_duration).to eq 50
          expect(user.pomodoro_setting.break_duration).to eq 10
        end
      end
    end

    context "異常系" do
      it "休憩時間が活動時間以上だとエラーメッセージが表示されること" do
        within('[data-pomodoro-setting-modal-target="modal"]') do
          fill_in "活動時間", with: 10
          fill_in "休憩時間", with: 10
          click_on "保存する"
        end

        # have_current_path がリダイレクト完了まで待機するため、reload はその後に行う
        expect(page).to have_current_path(mypage_path)

        aggregate_failures do
          expect(page).to have_content("活動時間未満")
          expect(user.pomodoro_setting.reload.work_duration).to eq 25
        end
      end
    end
  end

  describe "ポモドーロタイマーが設定値を参照すること", js: true do
    let!(:light_time) { create(:light_time, :current, user: user) }
    let!(:dark_time) { create(:dark_time, user: user) }

    before do
      user.pomodoro_setting.update!(work_duration: 45, break_duration: 15)
    end

    it "タイマー画面に設定された値(秒換算)が data 属性として埋め込まれること" do
      visit pomodoro_timer_activity_records_path

      timer = find('[data-controller="pomodoro"]')
      aggregate_failures do
        expect(timer["data-pomodoro-work-duration-value"]).to eq("2700")  # 45 * 60
        expect(timer["data-pomodoro-break-duration-value"]).to eq("900")  # 15 * 60
      end
    end
  end
end
