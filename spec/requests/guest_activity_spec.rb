require "rails_helper"

RSpec.describe "ゲストの最終アクセス時刻", type: :request do
  around { |example| freeze_time { example.run } }

  context "ゲストのとき" do
    let(:guest) { create(:user, :guest, last_request_at: 11.minutes.ago) }

    before { sign_in guest }

    it "最終更新から10分以上経っていれば更新すること" do
      expect { get mypage_path }.to change { guest.reload.last_request_at }.to(Time.current)
    end

    it "最終更新から10分未満なら更新しないこと" do
      guest.update_column(:last_request_at, 9.minutes.ago)

      expect { get mypage_path }.not_to change { guest.reload.last_request_at }
    end

    it "updated_at を動かさないこと（update_column を使うため）" do
      expect { get mypage_path }.not_to change { guest.reload.updated_at }
    end
  end

  context "実ユーザーのとき" do
    let(:user) { create(:user) }

    before { sign_in user }

    it "last_request_at を更新しないこと（削除対象ではないため読まれない）" do
      get mypage_path

      expect(user.reload.last_request_at).to be_nil
    end
  end
end
