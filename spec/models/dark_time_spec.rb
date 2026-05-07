require 'rails_helper'

RSpec.describe DarkTime, type: :model do
  describe "validations" do
    it "behaviorがあれば有効" do
      dark_time = build(:dark_time)
      expect(dark_time).to be_valid
    end

    it "behaviorがないと無効" do
      dark_time = build(:dark_time, behavior: nil)
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
  end

  describe "associations" do
    it "userに属している" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq(:belongs_to)
    end
  end
end
