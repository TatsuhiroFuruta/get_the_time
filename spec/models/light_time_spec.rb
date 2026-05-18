require 'rails_helper'

RSpec.describe LightTime, type: :model do
  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end

    it 'activity_records を dependent: :destroy で複数持つこと' do
      association = described_class.reflect_on_association(:activity_records)
      aggregate_failures do
        expect(association.macro).to eq :has_many
        expect(association.options[:dependent]).to eq :destroy
      end
    end
  end

  describe "バリデーション" do
    it "factory は有効であること" do
      expect(build(:light_time)).to be_valid
    end

    it "全ての値が正しい場合であれば有効であること" do
      light_time = build(:light_time)
      expect(light_time).to be_valid
    end

    it "action のみでも有効であること" do
      light_time = build(:light_time, characteristic: nil, desired_self: nil)
      expect(light_time).to be_valid
    end

    it "action が nil の場合は無効であること" do
      light_time = build(:light_time, action: nil)
      expect(light_time).to be_invalid
      expect(light_time.errors[:action]).to be_present
    end

    it "user が紐付いていない場合は無効であること" do
      light_time = build(:light_time, user: nil)
      expect(light_time).to be_invalid
      expect(light_time.errors[:user]).to be_present
    end
  end

  describe "デフォルト値" do
    it "is_current の初期値は false であること" do
      light_time = create(:light_time)
      expect(light_time.is_current).to be false
    end
  end

  describe ".switch_current!" do
    let(:user) { create(:user) }

    let!(:current_light_time) { create(:light_time, :current, user: user) }
    let!(:next_light_time) { create(:light_time, user: user) }
    let!(:third_light_time) { create(:light_time, user: user) }

    context "正常系" do
      it "指定した light_time が current になること" do
        described_class.switch_current!(user, next_light_time)
        expect(next_light_time.reload.is_current).to be true
      end

      it "他の light_time は current ではなくなること" do
        described_class.switch_current!(user, next_light_time)
        expect(current_light_time.reload.is_current).to be false
        expect(third_light_time.reload.is_current).to be false
      end

      it "current は1件だけになること" do
        described_class.switch_current!(user, next_light_time)

        expect(user.light_times.where(is_current: true).count).to eq 1
      end

      it "他ユーザーには影響しないこと" do
        other_user = create(:user)
        other_light_time = create(:light_time, :current, user: other_user)
        described_class.switch_current!(user, next_light_time)
        expect(other_light_time.reload.is_current).to be true
      end
    end

    context "異常系" do
      it "update! 失敗時は rollback されること" do
        allow(next_light_time).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        expect {described_class.switch_current!(user, next_light_time)
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(current_light_time.reload.is_current).to be true
        expect(next_light_time.reload.is_current).to be false
        expect(third_light_time.reload.is_current).to be false
      end
    end
  end

  describe '.ransackable_attributes' do
    it 'action カラムのみ検索可能' do
      expect(described_class.ransackable_attributes).to eq ["action"]
    end
  end
end
