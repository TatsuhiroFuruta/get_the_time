require "rails_helper"

RSpec.describe GuestUserBuilder, type: :service do
  subject(:user) { described_class.call }

  describe ".call" do
    it "ゲストユーザーを返すこと" do
      expect(user).to be_guest
    end

    it "last_request_at が入っていること（nil だと削除条件に永久にマッチしない）" do
      expect(user.last_request_at).to be_present
    end

    it "メールアドレスが guest_ で始まること" do
      expect(user.email).to match(/\Aguest_[0-9a-f]{16}@example\.com\z/)
    end

    it "呼ぶたびに別のユーザーが作られること" do
      expect { described_class.call }.to change(User.guest, :count).by(1)
    end

    it "ポモドーロ設定が作られること（after_create コールバック）" do
      expect(user.pomodoro_setting).to be_present
    end

    it "闇の時間が作られること" do
      expect(user.dark_time).to be_present
    end

    it "光の時間が作られ、current がちょうど1件であること" do
      aggregate_failures do
        expect(user.light_times.count).to eq GuestDemoData.light_times.size
        expect(user.light_times.where(is_current: true).count).to eq 1
      end
    end

    it "マイページの中核 UI が出る状態になっていること" do
      expect(user.light_and_dark_times_present?).to be true
    end

    it "活動記録が投入されること" do
      expect(user.activity_records.count).to eq GuestDemoData::SESSIONS.size
    end

    it "活動記録の desired_self_percentage が埋まっていること" do
      expect(user.activity_records.where(desired_self_percentage: nil)).to be_empty
    end

    # activity_records#index は order(created_at: :desc) なので、全件が同じ時刻だと
    # 並び順が不定になり、★を1つ押しただけで一覧が並び替わる。
    it "活動記録の created_at が重複しないこと" do
      created_ats = user.activity_records.pluck(:created_at)

      expect(created_ats.uniq.size).to eq created_ats.size
    end

    it "活動記録の created_at が ended_at と一致すること" do
      expect(user.activity_records.where("created_at IS DISTINCT FROM ended_at")).to be_empty
    end

    it "後悔記録と要約が投入されること" do
      aggregate_failures do
        expect(user.regret_records.count).to eq GuestDemoData::REGRETS.size
        expect(user.regret_summary).to be_present
      end
    end

    it "浄化タイマーに残時間があること" do
      expect(user.purification_time.remaining_time).to be > 0
    end

    # ここが設計上いちばん重要な不変条件。デモデータの日付を変えたときに
    # 静かに壊れるのを防ぐ。
    describe "浄化タイマーの不当付与が起きないこと" do
      it "今日の活動記録が0件であること" do
        expect(ActivityRecord.total_light_time_today(user)).to eq 0
      end

      it "払い出し済みブロックが0であること" do
        expect(user.purification_time.granted_blocks_for(Date.current)).to eq 0
      end

      it "閲覧者が30分の記録を1件作ったとき、付与は1ブロック分だけであること" do
        allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10)
        record = user.activity_records.create!(
          light_time: user.light_times.find_by(is_current: true),
          started_at: 30.minutes.ago,
          ended_at: Time.current,
          total_duration: 30,
          idle_duration: 0,
          satisfaction: 3, progress: 3, quality: 3, focus: 3, fatigue: 3
        )

        expect(PurificationTimeGranter.new(user).call(record)).to eq 10
      end
    end

    # GuestDemoData は今のところ呼ばれるたびに新しいハッシュを返すため、受け取った
    # 側が破壊しても実害は出ない。ただしその前提に寄りかかると、将来メモ化された
    # 瞬間に「1人目は成功し2人目から落ちる」という追いにくい壊れ方をする。
    # ここでは同じ配列を返し続ける状況を作って、その依存が無いことを固定する。
    describe "受け取ったデモデータを壊さないこと" do
      let(:demo_rows) { GuestDemoData.activity_records(Time.current) }

      before { allow(GuestDemoData).to receive(:activity_records).and_return(demo_rows) }

      it "呼び出し元のハッシュからキーを取り除かないこと" do
        described_class.call

        expect(demo_rows).to all(include(:light_time_index))
      end

      it "同じ配列を渡され続けても2人目以降を作れること" do
        described_class.call

        expect { described_class.call }.to change(User.guest, :count).by(1)
      end
    end

    it "失敗したときに中途半端なユーザーを残さないこと" do
      allow(RegretRecord).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid)

      expect {
        begin
          described_class.call
        rescue ActiveRecord::StatementInvalid
          nil
        end
      }.not_to change(User, :count)
    end
  end
end
