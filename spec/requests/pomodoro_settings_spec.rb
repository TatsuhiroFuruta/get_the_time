require "rails_helper"

RSpec.describe "PomodoroSettings", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "PATCH /pomodoro_setting" do
    let(:success_message) do
      I18n.t("defaults.flash_message.updated", item: PomodoroSetting.model_name.human)
    end

    context "正常系" do
      it "活動時間と休憩時間を更新できる" do
        patch pomodoro_setting_path, params: {
          pomodoro_setting: { work_duration: 50, break_duration: 10 }
        }

        user.pomodoro_setting.reload
        aggregate_failures do
          expect(response).to redirect_to(mypage_path)
          expect(flash[:notice]).to eq(success_message)
          expect(user.pomodoro_setting.work_duration).to eq 50
          expect(user.pomodoro_setting.break_duration).to eq 10
        end
      end

      it "範囲の下限値で更新できる" do
        patch pomodoro_setting_path, params: {
          pomodoro_setting: { work_duration: 10, break_duration: 1 }
        }

        aggregate_failures do
          expect(response).to redirect_to(mypage_path)
          expect(user.pomodoro_setting.reload.work_duration).to eq 10
          expect(user.pomodoro_setting.break_duration).to eq 1
        end
      end

      it "範囲の上限値で更新できる" do
        patch pomodoro_setting_path, params: {
          pomodoro_setting: { work_duration: 90, break_duration: 30 }
        }

        aggregate_failures do
          expect(response).to redirect_to(mypage_path)
          expect(user.pomodoro_setting.reload.work_duration).to eq 90
          expect(user.pomodoro_setting.break_duration).to eq 30
        end
      end
    end

    context "異常系" do
      it "活動時間が範囲外だと更新されず、alert が表示される" do
        patch pomodoro_setting_path, params: {
          pomodoro_setting: { work_duration: 9, break_duration: 5 }
        }

        aggregate_failures do
          expect(response).to redirect_to(mypage_path)
          expect(flash[:alert]).to be_present
          expect(user.pomodoro_setting.reload.work_duration).to eq 25
        end
      end

      it "休憩時間が範囲外だと更新されず、alert が表示される" do
        patch pomodoro_setting_path, params: {
          pomodoro_setting: { work_duration: 25, break_duration: 31 }
        }

        aggregate_failures do
          expect(response).to redirect_to(mypage_path)
          expect(flash[:alert]).to be_present
          expect(user.pomodoro_setting.reload.break_duration).to eq 5
        end
      end

      it "休憩時間が活動時間以上だと更新されず、alert が表示される" do
        patch pomodoro_setting_path, params: {
          pomodoro_setting: { work_duration: 10, break_duration: 10 }
        }

        aggregate_failures do
          expect(response).to redirect_to(mypage_path)
          expect(flash[:alert]).to include("活動時間未満")
          expect(user.pomodoro_setting.reload.work_duration).to eq 25
        end
      end
    end

    context "未ログインのとき" do
      before { sign_out user }

      it "ログインページへリダイレクトされる" do
        patch pomodoro_setting_path, params: {
          pomodoro_setting: { work_duration: 50, break_duration: 10 }
        }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
