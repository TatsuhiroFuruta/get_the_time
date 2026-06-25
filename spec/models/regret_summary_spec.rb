require "rails_helper"

RSpec.describe RegretSummary, type: :model do
  describe "バリデーション" do
    it "factory は有効であること" do
      expect(build(:regret_summary)).to be_valid
    end

    it "content が nil だと無効であること" do
      regret_summary = build(:regret_summary, content: nil)
      expect(regret_summary).to be_invalid
      expect(regret_summary.errors[:content]).to be_present
    end

    it "user が紐付いていないと無効であること" do
      regret_summary = build(:regret_summary, user: nil)
      expect(regret_summary).to be_invalid
      expect(regret_summary.errors[:user]).to be_present
    end
  end

  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end
  end
end
