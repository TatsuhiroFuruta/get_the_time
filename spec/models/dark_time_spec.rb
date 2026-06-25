require "rails_helper"

RSpec.describe DarkTime, type: :model do
  describe "バリデーション" do
    it "factory は有効であること" do
      expect(build(:dark_time)).to be_valid
    end

    it "全ての値が正しい場合であれば有効" do
      dark_time = build(:dark_time)
      expect(dark_time).to be_valid
    end

    it "behaviorのみで有効" do
      dark_time = build(:dark_time, characteristic: nil, unwanted_future: nil)
      expect(dark_time).to be_valid
    end

    it "behaviorがnilだと無効" do
      dark_time = build(:dark_time, behavior: nil)
      expect(dark_time).to be_invalid
      expect(dark_time.errors[:behavior]).to be_present
    end

    it "userが紐付いていないと無効" do
      dark_time = build(:dark_time, user: nil)
      expect(dark_time).to be_invalid
      expect(dark_time.errors[:user]).to be_present
    end
  end

  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end
  end

  describe "#merge_summary!" do
    let(:heading) { DarkTime::SUMMARY_HEADING }

    it "characteristic が空のときは見出しブロックだけになること" do
      dark_time = create(:dark_time, characteristic: nil)

      dark_time.merge_summary!("誘惑に流されやすい傾向がある")

      expect(dark_time.reload.characteristic).to eq("#{heading}\n誘惑に流されやすい傾向がある")
    end

    it "手入力の特徴があるときは温存して末尾に見出しブロックを追記すること" do
      dark_time = create(:dark_time, characteristic: "意志が弱い")

      dark_time.merge_summary!("夜更かしの傾向がある")

      aggregate_failures do
        expect(dark_time.reload.characteristic).to include("意志が弱い")
        expect(dark_time.characteristic).to include("#{heading}\n夜更かしの傾向がある")
        expect(dark_time.characteristic).to start_with("意志が弱い")
      end
    end

    it "再実行しても見出しブロックが重複せず差し替わること（肥大化しない）" do
      dark_time = create(:dark_time, characteristic: "意志が弱い")

      dark_time.merge_summary!("古い要約")
      dark_time.merge_summary!("新しい要約")

      aggregate_failures do
        expect(dark_time.reload.characteristic.scan(heading).size).to eq(1)
        expect(dark_time.characteristic).to include("新しい要約")
        expect(dark_time.characteristic).not_to include("古い要約")
        expect(dark_time.characteristic).to include("意志が弱い")
      end
    end
  end
end
