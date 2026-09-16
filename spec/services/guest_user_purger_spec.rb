require "rails_helper"

RSpec.describe GuestUserPurger, type: :service do
  # 無操作時間を明示的に作るため時刻を固定する
  around { |example| freeze_time { example.run } }

  def guest(last_request_at:)
    create(:user, :guest, last_request_at: last_request_at)
  end

  describe ".call" do
    it "1時間以上無操作のゲストを削除すること" do
      stale = guest(last_request_at: 61.minutes.ago)

      expect { described_class.call }.to change { User.exists?(stale.id) }.from(true).to(false)
    end

    it "1時間未満のゲストは残すこと" do
      fresh = guest(last_request_at: 59.minutes.ago)

      described_class.call

      expect(User.exists?(fresh.id)).to be true
    end

    it "実ユーザーは last_request_at が nil でも削除しないこと" do
      real = create(:user)

      described_class.call

      expect(User.exists?(real.id)).to be true
    end

    it "except_id に指定したゲストは削除しないこと" do
      mine = guest(last_request_at: 2.hours.ago)

      described_class.call(except_id: mine.id)

      expect(User.exists?(mine.id)).to be true
    end

    it "except_id が nil でも動くこと" do
      guest(last_request_at: 2.hours.ago)

      expect { described_class.call(except_id: nil) }.to change(User.guest, :count).by(-1)
    end

    it "削除した件数を返すこと" do
      2.times { guest(last_request_at: 2.hours.ago) }

      expect(described_class.call).to eq 2
    end

    it "関連データも一緒に消えること" do
      stale = GuestUserBuilder.call
      stale.update_column(:last_request_at, 2.hours.ago)

      described_class.call

      aggregate_failures do
        expect(ActivityRecord.where(user_id: stale.id)).to be_empty
        expect(RegretRecord.where(user_id: stale.id)).to be_empty
        expect(RegretSummary.where(user_id: stale.id)).to be_empty
        expect(PurificationTime.where(user_id: stale.id)).to be_empty
        expect(LightTime.where(user_id: stale.id)).to be_empty
        expect(DarkTime.where(user_id: stale.id)).to be_empty
        expect(PomodoroSetting.where(user_id: stale.id)).to be_empty
        expect(User.where(id: stale.id)).to be_empty
      end
    end

    it "1回の実行で削除する件数に上限があること" do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      2.times { guest(last_request_at: 2.hours.ago) }

      expect(described_class.call).to eq 1
    end

    it "削除対象がないとき 0 を返すこと" do
      expect(described_class.call).to eq 0
    end

    # 途中で失敗したとき、先に流れた DELETE だけがコミットされると
    # 「活動記録だけ消えて users 行が残る」中途半端な状態になる。
    # 呼び出し側は例外を握るだけなので画面には出ず、気づけない。
    it "途中で失敗したとき何も削除しないこと" do
      stale = GuestUserBuilder.call
      stale.update_column(:last_request_at, 2.hours.ago)
      allow(PomodoroSetting).to receive(:where).and_raise(ActiveRecord::StatementInvalid)

      begin
        described_class.call
      rescue ActiveRecord::StatementInvalid
        nil
      end

      aggregate_failures do
        expect(User.exists?(stale.id)).to be true
        expect(ActivityRecord.where(user_id: stale.id)).not_to be_empty
        expect(RegretRecord.where(user_id: stale.id)).not_to be_empty
      end
    end
  end
end
