require "rails_helper"

RSpec.describe LightTime, type: :model do
  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end

    it "activity_records を dependent: :destroy で複数持つこと" do
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
      aggregate_failures do
        expect(light_time).to be_invalid
        expect(light_time.errors[:action]).to be_present
      end
    end

    it "user が紐付いていない場合は無効であること" do
      light_time = build(:light_time, user: nil)
      aggregate_failures do
        expect(light_time).to be_invalid
        expect(light_time.errors[:user]).to be_present
      end
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
        aggregate_failures do
          expect(current_light_time.reload.is_current).to be false
          expect(third_light_time.reload.is_current).to be false
        end
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

    context "既に current のレコードを渡すとき" do
      it "渡した light_time は current のままであること" do
        described_class.switch_current!(user, current_light_time)
        expect(current_light_time.reload.is_current).to be true
      end

      it "current は1件のまま保たれること" do
        described_class.switch_current!(user, current_light_time)
        expect(user.light_times.where(is_current: true).count).to eq 1
      end

      it "他の light_time は current ではないままであること" do
        described_class.switch_current!(user, current_light_time)
        aggregate_failures do
          expect(next_light_time.reload.is_current).to be false
          expect(third_light_time.reload.is_current).to be false
        end
      end
    end

    context "異常系" do
      it "update! 失敗時は rollback されること" do
        allow(next_light_time).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        aggregate_failures do
          expect { described_class.switch_current!(user, next_light_time)
          }.to raise_error(ActiveRecord::RecordInvalid)

          expect(current_light_time.reload.is_current).to be true
          expect(next_light_time.reload.is_current).to be false
          expect(third_light_time.reload.is_current).to be false
        end
      end
    end
  end

  describe ".destroy_with_current_reassignment!" do
    let(:user) { create(:user) }

    context "current を削除するとき" do
      let!(:current_light_time) { create(:light_time, :current, user: user) }
      let!(:oldest_light_time) { create(:light_time, user: user) }
      let!(:newest_light_time) { create(:light_time, user: user) }

      it "レコードが削除されること" do
        expect {
          described_class.destroy_with_current_reassignment!(user, current_light_time)
        }.to change(described_class, :count).by(-1)
      end

      it "最古の残レコードが current に昇格すること" do
        described_class.destroy_with_current_reassignment!(user, current_light_time)
        aggregate_failures do
          expect(oldest_light_time.reload.is_current).to be true
          expect(newest_light_time.reload.is_current).to be false
          expect(user.light_times.where(is_current: true).count).to eq 1
        end
      end
    end

    context "非 current を削除するとき" do
      let!(:current_light_time) { create(:light_time, :current, user: user) }
      let!(:other_light_time) { create(:light_time, user: user) }

      it "current は変わらないこと" do
        described_class.destroy_with_current_reassignment!(user, other_light_time)
        expect(current_light_time.reload.is_current).to be true
      end
    end

    context "唯一の current を削除して 0 件になるとき" do
      let!(:only_light_time) { create(:light_time, :current, user: user) }

      it "エラーにならず 0 件になること" do
        aggregate_failures do
          expect {
            described_class.destroy_with_current_reassignment!(user, only_light_time)
          }.to change(user.light_times, :count).to(0)
        end
      end
    end

    context "昇格に失敗するとき" do
      let!(:current_light_time) { create(:light_time, :current, user: user) }
      let!(:next_light_time) { create(:light_time, user: user) }

      it "削除も rollback され current が保たれること" do
        allow(described_class).to receive(:switch_current!).and_raise(ActiveRecord::RecordInvalid)

        aggregate_failures do
          expect {
            described_class.destroy_with_current_reassignment!(user, current_light_time)
          }.to raise_error(ActiveRecord::RecordInvalid)

          expect(described_class.exists?(current_light_time.id)).to be true
          expect(current_light_time.reload.is_current).to be true
        end
      end
    end
  end

  describe ".ransackable_attributes" do
    it "action カラムのみ検索可能" do
      expect(described_class.ransackable_attributes).to eq [ "action" ]
    end
  end
end
