require "rails_helper"

RSpec.describe User, type: :model do
  # =========================================================
  # アソシエーション
  # =========================================================
  describe "アソシエーション" do
    it "dark_time を dependent: :destroy で1つ持つこと" do
      association = described_class.reflect_on_association(:dark_time)
      aggregate_failures do
        expect(association.macro).to eq :has_one
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "light_times を dependent: :destroy で複数持つこと" do
      association = described_class.reflect_on_association(:light_times)
      aggregate_failures do
        expect(association.macro).to eq :has_many
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "activity_records を dependent: :destroy で複数持つこと" do
      association = described_class.reflect_on_association(:activity_records)
      aggregate_failures do
        expect(association.macro).to eq :has_many
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "purification_time を dependent: :destroy で1つ持つこと" do
      association = described_class.reflect_on_association(:purification_time)
      aggregate_failures do
        expect(association.macro).to eq :has_one
        expect(association.options[:dependent]).to eq :destroy
      end
    end
  end

  describe "nameのバリデーション" do
    it "nameがあれば有効" do
      user = build(:user, name: "テスト")
      expect(user).to be_valid
    end

    it "nameがないと無効" do
      user = build(:user, name: nil)
      expect(user).to be_invalid
      expect(user.errors[:name]).to be_present
    end

    it "nameが30文字以内なら有効" do
      user = build(:user, name: "a" * 30)
      expect(user).to be_valid
    end

    it "nameが31文字以上だと無効" do
      user = build(:user, name: "a" * 31)
      expect(user).to be_invalid
      expect(user.errors[:name]).to be_present
    end
  end

  describe "passwordのバリデーション" do
    it "スペースを含むと無効" do
      user = build(:user,
        password: "pass word",
        password_confirmation: "pass word"
      )

      expect(user).to be_invalid
      # カスタムメッセージを書いているから、includeを記述
      expect(user.errors[:password]).to include("にスペースを含めることはできません")
    end

    it "スペースがなければ有効" do
      user = build(:user,
        password: "password123",
        password_confirmation: "password123"
      )

      expect(user).to be_valid
    end
  end
end
