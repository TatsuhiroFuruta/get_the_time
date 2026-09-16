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

  # ポモドーロと浄化タイマーの計測はすべてクライアント側で完結しており、計測中は
  # サーバへのリクエストが一切発生しない。そのままでは計測中のゲストが削除対象に
  # 入ってしまうため、計測中もクライアントから定期的に叩いてもらう。
  describe "POST /guest_heartbeat" do
    context "ゲストのとき" do
      let(:guest) { create(:user, :guest, last_request_at: 11.minutes.ago) }

      before { sign_in guest }

      it "last_request_at を更新すること" do
        expect { post guest_heartbeat_path }.to change { guest.reload.last_request_at }.to(Time.current)
      end

      it "本文を返さないこと" do
        post guest_heartbeat_path

        expect(response).to have_http_status(:no_content)
      end
    end

    context "未ログインのとき" do
      it "認証を要求すること" do
        post guest_heartbeat_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "ハートビートの設置" do
    it "ゲストのページには置かれること" do
      sign_in create(:user, :guest)
      get mypage_path

      expect(response.body).to include('data-controller="guest-heartbeat"')
    end

    it "実ユーザーのページには置かれないこと" do
      sign_in create(:user)
      get mypage_path

      expect(response.body).not_to include('data-controller="guest-heartbeat"')
    end
  end
end
