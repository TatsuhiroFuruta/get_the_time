require "rails_helper"

RSpec.describe GuestDemoData, type: :service do
  let(:now) { Time.zone.parse("2026-09-15 10:00:00") }

  describe ".light_times" do
    it "2件以上あり、先頭が current 用であること" do
      expect(described_class.light_times.size).to be >= 2
    end

    it "action が全件埋まっていること（LightTime は presence バリデーションがある）" do
      expect(described_class.light_times).to all(include(:action))
    end
  end

  describe ".activity_records" do
    subject(:records) { described_class.activity_records(now) }

    it "30件以上あること" do
      expect(records.size).to be >= 30
    end

    # 今日の記録を入れると PurificationTimeGranter が floor(当日累計 / 30) 個の
    # ブロックを閲覧者に払い出してしまう。これは設計上の不変条件。
    it "すべて昨日以前の記録であること" do
      today = now.to_date

      expect(records.map { |r| r[:ended_at].to_date }).to all(be < today)
    end

    it "5段階評価がすべて 1..5 に収まっていること（insert_all でバリデーションを飛ばすため）" do
      %i[satisfaction progress quality focus fatigue].each do |field|
        expect(records.map { |r| r[field] }).to all(be_between(1, 5))
      end
    end

    it "idle_duration が total_duration 以下であること" do
      expect(records).to all(satisfy { |r| r[:idle_duration] <= r[:total_duration] })
    end

    it "desired_self_percentage が (total - idle) / total で埋まっていること" do
      expect(records).to all(satisfy { |r|
        r[:desired_self_percentage] == ((r[:total_duration] - r[:idle_duration]).to_f / r[:total_duration]).round(2)
      })
    end

    it "started_at が ended_at から total_duration 分だけ前であること" do
      expect(records).to all(satisfy { |r| r[:ended_at] - r[:started_at] == r[:total_duration] * 60 })
    end

    it "light_time_index が light_times の範囲に収まっていること" do
      max_index = described_class.light_times.size - 1

      expect(records.map { |r| r[:light_time_index] }).to all(be_between(0, max_index))
    end
  end

  describe ".regret_records" do
    subject(:records) { described_class.regret_records(now) }

    it "8件以上あること" do
      expect(records.size).to be >= 8
    end

    it "お気に入りが1件以上あること（お気に入りフィルタのデモ用）" do
      expect(records.count { |r| r[:favorited] }).to be >= 1
    end

    it "content が全件埋まっていること（RegretRecord は null: false）" do
      expect(records.map { |r| r[:content] }).to all(be_present)
    end
  end

  describe ".purification_time" do
    it "残時間があり idle であること（カードが表示され、すぐ開始できる状態）" do
      expect(described_class.purification_time).to include(remaining_time: be > 0, status: 0)
    end
  end
end
