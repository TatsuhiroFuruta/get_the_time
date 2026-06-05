require "rails_helper"

RSpec.describe RegretRecord, type: :model do
  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end
  end

  describe "バリデーション" do
    it "factory は有効であること" do
      expect(build(:regret_record)).to be_valid
    end

    it "title と content が入力されていれば有効であること" do
      regret_record = build(:regret_record, title: "後悔した日", content: "やるべきことができなかった")
      expect(regret_record).to be_valid
    end

    it "title が空でも content があれば有効であること" do
      regret_record = build(:regret_record, title: nil)
      expect(regret_record).to be_valid
    end

    it "content が nil の場合は無効であること" do
      regret_record = build(:regret_record, content: nil)
      expect(regret_record).to be_invalid
      expect(regret_record.errors[:content]).to be_present
    end

    it "user が紐付いていない場合は無効であること" do
      regret_record = build(:regret_record, user: nil)
      expect(regret_record).to be_invalid
      expect(regret_record.errors[:user]).to be_present
    end
  end

  describe "ransack の検索可能カラム" do
    it "検索可能なカラムが favorited のみであること" do
      expect(described_class.ransackable_attributes).to eq [ "favorited" ]
    end

    it "検索可能な関連付けが無いこと" do
      expect(described_class.ransackable_associations).to eq []
    end
  end
end
