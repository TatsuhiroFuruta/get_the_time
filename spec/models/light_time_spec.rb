require 'rails_helper'

RSpec.describe LightTime, type: :model do
  let(:user) { create(:user) }

  describe "バリデーション" do
    context "正常系" do
      it "全ての値が正しい場合、有効であること" do
        light_time = build(:light_time, user: user)
        expect(light_time).to be_valid
      end

      it "action のみで有効であること" do
        light_time = build(:light_time, user: user, characteristic: nil, desired_self: nil)
        expect(light_time).to be_valid
      end
    end

    context "異常系" do
      it "action が空の場合、無効であること" do
        light_time = build(:light_time, user: user, action: "")
        expect(light_time).to be_invalid
        expect(light_time.errors[:action]).to be_present
      end

      it "action が空白文字の場合、無効であること" do
        light_time = build(:light_time, user: user, action: "   ")
        expect(light_time).to be_invalid
        expect(light_time.errors[:action]).to be_present
      end

      it "action が nil の場合、無効であること" do
        light_time = build(:light_time, user: user, action: nil)
        expect(light_time).to be_invalid
        expect(light_time.errors[:action]).to be_present
      end

      it "user が紐付いていない場合、無効であること" do
        light_time = build(:light_time, user: nil)
        expect(light_time).to be_invalid
        expect(light_time.errors[:user]).to be_present
      end
    end
  end

  describe "デフォルト値" do
    it "is_current のデフォルト値が false であること" do
      light_time = create(:light_time, user: user)
      expect(light_time.is_current).to be false
    end
  end

  describe ".switch_current!" do
    let!(:light_time1) { create(:light_time, :current, user: user, action: "朝のヨガ", created_at: 3.days.ago) }
    let!(:light_time2) { create(:light_time, user: user, action: "夜の読書", created_at: 2.days.ago) }
    let!(:light_time3) { create(:light_time, user: user, action: "昼の瞑想", created_at: 1.day.ago) }

    context "正常系" do
      it "指定した LightTime が current になること" do
        LightTime.switch_current!(user, light_time2)
        expect(light_time2.reload.is_current).to be true
      end

      it "他の LightTime が current でなくなること" do
        LightTime.switch_current!(user, light_time2)
        expect(light_time1.reload.is_current).to be false
        expect(light_time3.reload.is_current).to be false
      end

      it "同じユーザーの LightTime のみ影響を受けること" do
        other_user = create(:user)
        other_light_time = create(:light_time, :current, user: other_user, action: "他人の習慣")

        LightTime.switch_current!(user, light_time2)
        expect(other_light_time.reload.is_current).to be true
      end

      it "トランザクション内で処理されること" do
        allow(LightTime).to receive(:transaction).and_call_original
        LightTime.switch_current!(user, light_time2)
        expect(LightTime).to have_received(:transaction)
      end
    end

    context "異常系" do
      it "存在しない LightTime を指定するとエラーになること" do
        expect {
          LightTime.switch_current!(user, nil)
        }.to raise_error(NoMethodError)
      end

      it "他人の LightTime を指定しても current にならないこと" do
        other_user = create(:user)
        other_light_time = create(:light_time, user: other_user, action: "他人の習慣")

        LightTime.switch_current!(user, other_light_time)
        expect(other_light_time.reload.is_current).to be false
      end

      it 'エラー時にロールバックされること' do
        # light_time2 の update! でエラーを発生させる
        allow(light_time2).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        # エラーが発生することを確認
        expect {
          LightTime.switch_current!(user, light_time2)
        }.to raise_error(ActiveRecord::RecordInvalid)

        # ロールバックされていることを確認
        expect(light_time1.reload.is_current).to be true  # 元の状態に戻っている
        expect(light_time2.reload.is_current).to be false # 変更されていない
        expect(light_time3.reload.is_current).to be false # 変更されていない
      end
    end
  end

  describe "current の自動設定" do
    context "current を削除した場合" do
      let!(:current_light_time) { create(:light_time, :current, user: user, action: "現在の習慣", created_at: 2.days.ago) }
      let!(:next_light_time) { create(:light_time, user: user, action: "次の習慣", created_at: 1.day.ago) }

      it "次の LightTime が current になること" do
        current_light_time.destroy
        expect(next_light_time.reload.is_current).to be true
      end

      it "作成日時が最も古い LightTime が current になること" do
        oldest_light_time = create(:light_time, user: user, action: "最も古い", created_at: 3.days.ago)
        newer_light_time = create(:light_time, user: user, action: "新しい", created_at: 1.hour.ago)

        current_light_time.destroy

        expect(oldest_light_time.reload.is_current).to be true
        expect(newer_light_time.reload.is_current).to be false
      end
    end

    context "current でない LightTime を削除した場合" do
      let!(:current_light_time) { create(:light_time, :current, user: user, action: "現在の習慣") }
      let!(:non_current_light_time) { create(:light_time, user: user, action: "他の習慣") }
      it "current は変わらないこと" do
        non_current_light_time.destroy
        expect(current_light_time.reload.is_current).to be true
      end
    end

    context "最後の LightTime を削除した場合" do
      let!(:only_light_time) { create(:light_time, :current, user: user, action: "唯一の習慣") }

      it "エラーにならないこと" do
        expect {
          only_light_time.destroy
        }.not_to raise_error
      end

      it "データベースから削除されること" do
        only_light_time.destroy
        expect(LightTime.where(id: only_light_time.id)).not_to exist
      end
    end
  end

  describe "アソシエーション" do
    it "Userに属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end
  end
end
