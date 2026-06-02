require "rails_helper"

RSpec.describe ActivityRecordsHelper, type: :helper do
  describe "#desired_self_level" do
    it "未計測(nil)のとき 0 を返すこと" do
      expect(helper.desired_self_level(nil)).to eq 0
    end

    it "0%(0.0)のとき 0 を返すこと" do
      expect(helper.desired_self_level(0.0)).to eq 0
    end

    it "0%超〜20%未満のとき 1 を返すこと" do
      aggregate_failures do
        expect(helper.desired_self_level(0.01)).to eq 1
        expect(helper.desired_self_level(0.199)).to eq 1
      end
    end

    it "20%〜40%未満のとき 2 を返すこと" do
      aggregate_failures do
        expect(helper.desired_self_level(0.20)).to eq 2
        expect(helper.desired_self_level(0.399)).to eq 2
      end
    end

    it "40%〜60%未満のとき 3 を返すこと" do
      aggregate_failures do
        expect(helper.desired_self_level(0.40)).to eq 3
        expect(helper.desired_self_level(0.599)).to eq 3
      end
    end

    it "60%〜80%未満のとき 4 を返すこと" do
      aggregate_failures do
        expect(helper.desired_self_level(0.60)).to eq 4
        expect(helper.desired_self_level(0.799)).to eq 4
      end
    end

    it "80%〜100%のとき 5 を返すこと" do
      aggregate_failures do
        expect(helper.desired_self_level(0.80)).to eq 5
        expect(helper.desired_self_level(1.0)).to eq 5
      end
    end
  end

  describe "#truncate_card_text" do
    it "未記入のとき「...」を返すこと" do
      aggregate_failures do
        expect(helper.truncate_card_text(nil)).to eq "..."
        expect(helper.truncate_card_text("")).to eq "..."
      end
    end

    it "10文字以下はそのまま返すこと" do
      expect(helper.truncate_card_text("今日もよく頑張った")).to eq "今日もよく頑張った"
    end

    it "10文字超は先頭10文字+「...」で省略すること" do
      expect(helper.truncate_card_text("今日もよく頑張ったよヨヨヨ")).to eq "今日もよく頑張ったよ..."
    end
  end
end
