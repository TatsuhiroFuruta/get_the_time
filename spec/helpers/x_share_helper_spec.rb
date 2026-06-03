require "rails_helper"

RSpec.describe XShareHelper, type: :helper do
  describe "#format_date_ja" do
    it "JST の和暦なし日本語日付表記（前ゼロなし）を返すこと" do
      time = Time.zone.local(2026, 6, 2, 14, 30)
      expect(helper.format_date_ja(time)).to eq "2026年6月2日"
    end

    it "UTC の時刻を JST に変換して日付を返すこと" do
      # 2026-06-02 23:30 UTC は JST では 2026-06-03 08:30
      time = Time.utc(2026, 6, 2, 23, 30)
      expect(helper.format_date_ja(time)).to eq "2026年6月3日"
    end
  end

  describe "#format_time_ja" do
    it "JST の時刻表記（前ゼロなし）を返すこと" do
      time = Time.zone.local(2026, 6, 2, 9, 5)
      expect(helper.format_time_ja(time)).to eq "9時5分"
    end
  end

  describe "#x_share_overall_text" do
    it "「〜年〜月〜日の本来の自分は ◯◯ % です」の文面を返すこと" do
      date = Time.zone.local(2026, 6, 2, 12, 0)
      expect(helper.x_share_overall_text(0.89, date: date))
        .to eq "2026年6月2日の本来の自分は 89.0 % です"
    end
  end

  describe "#x_share_activity_text" do
    it "「〜年〜月〜日〜時〜分開始の約〜分間の活動における今日の本来の自分は ◯◯ % です」の文面を返すこと" do
      started_at = Time.zone.local(2026, 6, 2, 14, 30)
      expect(helper.x_share_activity_text(0.5, started_at: started_at, total_duration: 60))
        .to eq "2026年6月2日14時30分開始の約60分間の活動における今日の本来の自分は 50.0 % です"
    end
  end

  describe "#x_share_message" do
    it "本文 → ハッシュタグ → URL の順に改行で組み立てること" do
      message = helper.x_share_message("本文", hashtags: %w[GetTheTime 本来の自分], url: "https://example.com/")
      expect(message).to eq "本文\n#GetTheTime #本来の自分\nhttps://example.com/"
    end

    it "ハッシュタグが無いときはその行を省くこと" do
      message = helper.x_share_message("本文", url: "https://example.com/")
      expect(message).to eq "本文\nhttps://example.com/"
    end

    it "URL が無いときは URL を省くこと" do
      message = helper.x_share_message("本文", hashtags: %w[GetTheTime])
      expect(message).to eq "本文\n#GetTheTime"
    end
  end

  describe "#x_intent_url" do
    it "テキストを URL エンコードして投稿画面 URL を返すこと" do
      url = helper.x_intent_url("テスト 本来の自分")
      aggregate_failures do
        expect(url).to start_with("https://twitter.com/intent/tweet?")
        expect(url).to include("text=#{CGI.escape("テスト 本来の自分")}")
      end
    end
  end
end
