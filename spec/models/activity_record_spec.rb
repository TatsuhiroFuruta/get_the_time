require "rails_helper"

RSpec.describe ActivityRecord, type: :model do
  let(:user)       { create(:user) }
  # is_current: false がデフォルトのため :current トレイトを明示
  let(:light_time) { create(:light_time, :current, user: user) }

  # =========================================================
  # アソシエーション
  # =========================================================
  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end

    it "LightTime に属していること" do
      association = described_class.reflect_on_association(:light_time)
      expect(association.macro).to eq :belongs_to
    end
  end

  # =========================================================
  # バリデーション
  # =========================================================
  describe "バリデーション" do
    context "正常な値のとき" do
      subject { build(:activity_record, user: user, light_time: light_time) }

      it { is_expected.to be_valid }
    end

    describe "idle_duration" do
      subject(:activity_record) { build(:activity_record, user: user, light_time: light_time) }

      it "0 は有効" do
        activity_record.idle_duration = 0
        expect(activity_record).to be_valid
      end

      it "負の値は無効" do
        activity_record.idle_duration = -1
        expect(activity_record).to be_invalid
        expect(activity_record.errors[:idle_duration]).to be_present
      end

      it "total_duration を超えると無効" do
        activity_record.idle_duration = activity_record.total_duration + 1
        expect(activity_record).to be_invalid
        expect(activity_record.errors[:idle_duration]).to include("は合計時間以下にしてください")
      end

      it "total_duration と同値は有効" do
        activity_record.idle_duration = activity_record.total_duration
        expect(activity_record).to be_valid
      end
    end

    describe "5段階評価カラム" do
      subject(:activity_record) { build(:activity_record, user: user, light_time: light_time) }

      %i[satisfaction progress quality focus fatigue].each do |attr|
        context attr.to_s do
          (1..5).each do |v|
            it "#{v} は有効" do
              activity_record.send(:"#{attr}=", v)
              expect(activity_record).to be_valid
            end
          end

          [ 0, 6 ].each do |v|
            it "#{v} は無効" do
              activity_record.send(:"#{attr}=", v)
              expect(activity_record).to be_invalid
              expect(activity_record.errors[attr]).to be_present
            end
          end
        end
      end
    end
  end

  # =========================================================
  # .sample_purification_minutes
  # =========================================================
  describe ".sample_purification_minutes" do
    subject { described_class.sample_purification_minutes }

    [
      [ 0,  8 ],
      [ 59, 8 ],
      [ 60, 10 ],
      [ 89, 10 ],
      [ 90, 13 ],
      [ 98, 13 ],
      [ 99, 15 ]
    ].each do |rand_val, expected|
      context "rand が #{rand_val} を返すとき" do
        before { allow(described_class).to receive(:rand).with(100).and_return(rand_val) }

        it "#{expected} 分を返すこと" do
          is_expected.to eq expected
        end
      end
    end

    it "スタブなしでも有効な付与分数を返すこと" do
      is_expected.to be_in([ 8, 10, 13, 15 ])
    end
  end

  # =========================================================
  # .calculate_purification_time
  # =========================================================
  describe ".calculate_purification_time" do
    subject { described_class.calculate_purification_time(total_duration) }

    before { allow(described_class).to receive(:sample_purification_minutes).and_return(10) }

    context "nil のとき" do
      let(:total_duration) { nil }
      it { is_expected.to eq 0 }
    end

    context "0 分のとき" do
      let(:total_duration) { 0 }
      it { is_expected.to eq 0 }
    end

    context "29 分（30 未満）のとき" do
      let(:total_duration) { 29 }
      it { is_expected.to eq 0 }
    end

    context "30 分のとき" do
      let(:total_duration) { 30 }

      it "sample_purification_minutes を 1 回呼ぶこと" do
        subject
        expect(described_class).to have_received(:sample_purification_minutes).once
      end

      it { is_expected.to eq 10 }
    end

    context "59 分のとき" do
      let(:total_duration) { 59 }
      it { is_expected.to eq 10 }
    end

    context "60 分のとき" do
      let(:total_duration) { 60 }

      it "sample_purification_minutes を 2 回呼ぶこと" do
        subject
        expect(described_class).to have_received(:sample_purification_minutes).twice
      end

      it { is_expected.to eq 20 }
    end

    context "120 分のとき" do
      let(:total_duration) { 120 }
      it { is_expected.to eq 40 }
    end

    context "スタブなしで 30 分のとき" do
      before { allow(described_class).to receive(:sample_purification_minutes).and_call_original }
      let(:total_duration) { 30 }

      it "有効な付与分数を返すこと" do
        is_expected.to be_in([ 8, 10, 13, 15 ])
      end
    end
  end

  # =========================================================
  # .total_light_time_today
  # =========================================================
  describe ".total_light_time_today" do
    subject { described_class.total_light_time_today(user) }

    context "今日の記録がないとき" do
      it { is_expected.to eq 0 }
    end

    context "今日の記録が複数あるとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, total_duration: 30)
        create(:activity_record, user: user, light_time: light_time, total_duration: 45)
      end

      it "合計値を返すこと" do
        is_expected.to eq 75
      end
    end

    context "昨日の記録しかないとき" do
      before { create(:activity_record, :yesterday, user: user, light_time: light_time) }

      it { is_expected.to eq 0 }
    end

    context "別ユーザーの記録は集計に含まないこと" do
      let(:other_user)  { create(:user) }
      let(:other_light) { create(:light_time, :current, user: other_user) }

      before do
        create(:activity_record, user: other_user, light_time: other_light, total_duration: 999)
      end

      it { is_expected.to eq 0 }
    end
  end

  # =========================================================
  # before_save: calculate_desired_self_percentage
  # =========================================================
  describe "desired_self_percentage の計算" do
    it "正しい割合が保存されること" do
      activity_record = create(:activity_record, user: user, light_time: light_time,
                      total_duration: 100, idle_duration: 20)
      # (100 - 20) / 100.0 = 0.8
      expect(activity_record.desired_self_percentage).to be_within(0.001).of(0.8)
    end

    it "idle_duration が 0 のとき 1.0 になること" do
      activity_record = create(:activity_record, user: user, light_time: light_time,
                      total_duration: 60, idle_duration: 0)
      expect(activity_record.desired_self_percentage).to be_within(0.001).of(1.0)
    end

    it "total_duration が 0 のときは nil のままであること" do
      activity_record = build(:activity_record, user: user, light_time: light_time,
                     total_duration: 0, idle_duration: 0)
      activity_record.save(validate: false)
      expect(activity_record.desired_self_percentage).to be_nil
    end
  end

  # =========================================================
  # after_create: grant_purification_time
  # =========================================================
  describe "grant_purification_time コールバック" do
    before { allow(described_class).to receive(:sample_purification_minutes).and_return(10) }

    context "PurificationTime が既に存在するとき" do
      let!(:purification_time) { create(:purification_time, user: user, remaining_time: 0) }

      context ":long_session (90 分) のとき" do
        it "remaining_time に 1800 秒 (3 ブロック × 10 分) 加算されること" do
          create(:activity_record, :long_session, user: user, light_time: light_time)
          expect(purification_time.reload.remaining_time).to eq 1800
        end
      end

      context ":short_session (20 分) のとき" do
        it "remaining_time が変化しないこと" do
          create(:activity_record, :short_session, user: user, light_time: light_time)
          expect(purification_time.reload.remaining_time).to eq 0
        end
      end
    end

    context "PurificationTime がまだ存在しないとき" do
      context ":long_session (90 分) のとき" do
        it "PurificationTime が新規作成されて 1800 秒セットされること" do
          expect {
            create(:activity_record, :long_session, user: user, light_time: light_time)
          }.to change(PurificationTime, :count).by(1)

          expect(user.reload.purification_time.remaining_time).to eq 1800
        end
      end

      context ":short_session (20 分) のとき" do
        it "PurificationTime は作成されないこと" do
          expect {
            create(:activity_record, :short_session, user: user, light_time: light_time)
          }.not_to change(PurificationTime, :count)
        end
      end
    end
  end

  # =========================================================
  # ransack の検索可能カラム
  # =========================================================
  describe "ransack の検索可能カラム" do
    it "検索可能なカラムが comment のみであること" do
      expect(described_class.ransackable_attributes).to eq [ "comment" ]
    end

    it "検索可能な関連付けが light_time のみであること" do
      expect(described_class.ransackable_associations).to eq [ "light_time" ]
    end
  end
end
