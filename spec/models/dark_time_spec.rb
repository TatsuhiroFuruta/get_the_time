require 'rails_helper'

RSpec.describe DarkTime, type: :model do
  describe "バリデーション" do
    it "全ての値が正しい場合であれば有効" do
      dark_time = build(:dark_time)
      expect(dark_time).to be_valid
    end

    it "characteristicとunwanted_futureがnilでも有効" do
      dark_time = build(:dark_time, characteristic: nil, unwanted_future: nil)
      expect(dark_time).to be_valid
    end

    it "behaviorがnilだと無効" do
      dark_time = build(:dark_time, behavior: nil)
      expect(dark_time).to be_invalid
      expect(dark_time.errors[:behavior]).to be_present
    end

    it "behaviorが空文字列だと無効" do
      dark_time = build(:dark_time, behavior: "")
      expect(dark_time).to be_invalid
      expect(dark_time.errors[:behavior]).to be_present
    end

    it "behaviorが空白文字だと無効" do
      dark_time = build(:dark_time, behavior: "   ")
      expect(dark_time).to be_invalid
      expect(dark_time.errors[:behavior]).to be_present
    end

    it "userごとに1件のみ" do
      user = create(:user)
      create(:dark_time, user: user)

      second = build(:dark_time, user: user)
      expect(second).to be_invalid
      expect(second.errors[:user_id]).to be_present
    end

    it "userが紐付いていないと無効" do
      dark_time = build(:dark_time, user: nil)
      expect(dark_time).to be_invalid
      expect(dark_time.errors[:user]).to be_present
    end
  end

  describe "アソシエーション" do
    it "Userに属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq(:belongs_to)
    end
  end
end
