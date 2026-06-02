# spec/helpers/application_helper_spec.rb
require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#format_seconds_to_mmss" do
    it "60秒を「1 分 00 秒」に変換すること" do
      expect(helper.format_seconds_to_mmss(60)).to eq "1 分 00 秒"
    end

    it "125秒を「2 分 05 秒」に変換すること(秒のゼロパディング)" do
      expect(helper.format_seconds_to_mmss(125)).to eq "2 分 05 秒"
    end

    it "0秒を「0 分 00 秒」に変換すること" do
      expect(helper.format_seconds_to_mmss(0)).to eq "0 分 00 秒"
    end

    it "3600秒を「60 分 00 秒」に変換すること" do
      expect(helper.format_seconds_to_mmss(3600)).to eq "60 分 00 秒"
    end
  end

  describe "#format_minutes_to_hm" do
    it "60分を「1 時間 00 分」に変換すること" do
      expect(helper.format_minutes_to_hm(60)).to eq "1 時間 00 分"
    end

    it "125分を「2 時間 05 分」に変換すること" do
      expect(helper.format_minutes_to_hm(125)).to eq "2 時間 05 分"
    end

    it "0分を「0 時間 00 分」に変換すること" do
      expect(helper.format_minutes_to_hm(0)).to eq "0 時間 00 分"
    end
  end

  describe "#display_percentage" do
    it "nil のとき nil を返すこと(表示文言はビュー側に委譲)" do
      expect(helper.display_percentage(nil)).to be_nil
    end

    it "0.8 を「80.0 %」に変換すること(小数1桁)" do
      expect(helper.display_percentage(0.8)).to eq "80.0 %"
    end

    it "小数第2位を四捨五入して第1位までにすること" do
      aggregate_failures do
        expect(helper.display_percentage(0.3333)).to eq "33.3 %" # 切り下げ
        expect(helper.display_percentage(0.6666)).to eq "66.7 %" # 切り上げ
      end
    end

    it "1.0 を「100.0 %」に変換すること" do
      expect(helper.display_percentage(1.0)).to eq "100.0 %"
    end
  end

  describe "#format_datetime" do
    it "DateTime をフォーマットすること" do
      dt = Time.zone.local(2024, 1, 15, 14, 30)
      expect(helper.format_datetime(dt)).to eq "2024-01-15 14:30"
    end

    it "nil のとき nil を返すこと" do
      expect(helper.format_datetime(nil)).to be_nil
    end
  end
end
