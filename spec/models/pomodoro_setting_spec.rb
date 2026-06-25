require "rails_helper"

RSpec.describe PomodoroSetting, type: :model do
  # =========================================================
  # アソシエーション
  # =========================================================
  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end
  end

  # =========================================================
  # バリデーション
  # =========================================================
  describe "バリデーション" do
    subject(:pomodoro_setting) { build(:pomodoro_setting) }

    context "デフォルト値(25/5)のとき" do
      it { is_expected.to be_valid }
    end

    describe "work_duration" do
      it "10 は有効" do
        pomodoro_setting.work_duration = 10
        pomodoro_setting.break_duration = 1
        expect(pomodoro_setting).to be_valid
      end

      it "90 は有効" do
        pomodoro_setting.work_duration = 90
        expect(pomodoro_setting).to be_valid
      end

      it "9 は無効" do
        pomodoro_setting.work_duration = 9
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:work_duration]).to be_present
        end
      end

      it "91 は無効" do
        pomodoro_setting.work_duration = 91
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:work_duration]).to be_present
        end
      end

      it "nil は無効" do
        pomodoro_setting.work_duration = nil
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:work_duration]).to be_present
        end
      end

      it "整数以外は無効" do
        pomodoro_setting.work_duration = 25.5
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:work_duration]).to be_present
        end
      end
    end

    describe "break_duration" do
      it "1 は有効" do
        pomodoro_setting.break_duration = 1
        expect(pomodoro_setting).to be_valid
      end

      it "30 は有効 (活動時間が31以上であれば)" do
        pomodoro_setting.work_duration = 60
        pomodoro_setting.break_duration = 30
        expect(pomodoro_setting).to be_valid
      end

      it "0 は無効" do
        pomodoro_setting.break_duration = 0
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:break_duration]).to be_present
        end
      end

      it "31 は無効" do
        pomodoro_setting.break_duration = 31
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:break_duration]).to be_present
        end
      end

      it "nil は無効" do
        pomodoro_setting.break_duration = nil
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:break_duration]).to be_present
        end
      end
    end

    describe "break_duration < work_duration の制約" do
      it "活動時間より短い休憩時間は有効" do
        pomodoro_setting.work_duration = 25
        pomodoro_setting.break_duration = 5
        expect(pomodoro_setting).to be_valid
      end

      it "活動時間と同値の休憩時間は無効" do
        pomodoro_setting.work_duration = 10
        pomodoro_setting.break_duration = 10
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:break_duration]).to include("は活動時間未満で設定してください")
        end
      end

      it "活動時間より長い休憩時間は無効" do
        pomodoro_setting.work_duration = 10
        pomodoro_setting.break_duration = 20
        aggregate_failures do
          expect(pomodoro_setting).to be_invalid
          expect(pomodoro_setting.errors[:break_duration]).to include("は活動時間未満で設定してください")
        end
      end
    end
  end
end
