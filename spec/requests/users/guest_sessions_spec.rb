require "rails_helper"

RSpec.describe "Users::GuestSessions", type: :request do
  describe "POST /guest_sign_in" do
    it "ゲストを作成してマイページへ遷移すること" do
      expect { post guest_sign_in_path }.to change(User.guest, :count).by(1)

      expect(response).to redirect_to(mypage_path)
    end

    it "ログイン状態になること" do
      post guest_sign_in_path
      follow_redirect!

      expect(response).to have_http_status(:ok)
    end

    it "デモデータが投入されていること" do
      post guest_sign_in_path
      guest = User.guest.last

      aggregate_failures do
        expect(guest.light_and_dark_times_present?).to be true
        expect(guest.activity_records).not_to be_empty
        expect(guest.regret_summary).to be_present
      end
    end

    it "成功メッセージを出すこと" do
      post guest_sign_in_path

      expect(flash[:notice]).to eq I18n.t("users.guest_sessions.flash_message.signed_in")
    end

    it "無操作のゲストを掃除すること" do
      stale = create(:user, :guest, last_request_at: 2.hours.ago)

      post guest_sign_in_path

      expect(User.exists?(stale.id)).to be false
    end

    it "掃除が失敗してもログインは通すこと" do
      allow(GuestUserPurger).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { post guest_sign_in_path }.to change(User.guest, :count).by(1)

      expect(response).to redirect_to(mypage_path)
    end

    it "レート制限を超えたらトップページへ戻すこと" do
      # test 環境の cache_store は :null_store で increment が nil を返すため、
      # 回数超過を再現するには increment の戻り値を差し替える。
      # rate_limit は store をクラス定義時に束縛するので、その同じオブジェクトを差し替える。
      # 上限そのものは定数から取る。数値を直書きすると、上限を上げたときに
      # 「超えていない値」でテストが通り続け、検証になっていないことに気づけない。
      over_limit = Users::GuestSessionsController::MAX_SIGN_INS_PER_HOUR + 1
      allow(Users::GuestSessionsController.cache_store).to receive(:increment).and_return(over_limit)

      expect { post guest_sign_in_path }.not_to change(User.guest, :count)

      aggregate_failures do
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq I18n.t("users.guest_sessions.flash_message.rate_limited")
      end
    end
  end

  # sign_in は Warden のユーザーを無条件に差し替えるため、ログイン済みの人が
  # 別タブやブラウザバックでこの経路を踏むと、黙って本アカウントから使い捨ての
  # ゲストへ入れ替わってしまう。
  describe "ログイン済みのとき" do
    context "実ユーザー" do
      let(:user) { create(:user) }

      before { sign_in user }

      it "ゲストを作らずマイページへ戻すこと" do
        expect { post guest_sign_in_path }.not_to change(User.guest, :count)

        expect(response).to redirect_to(mypage_path)
      end

      it "ログイン中のアカウントが入れ替わらないこと" do
        post guest_sign_in_path
        get mypage_path

        expect(response.body).to include(user.name)
      end

      # before_action は宣言順に走り、redirect_if_signed_in が rate_limit より先に
      # 書かれているのでチェーンはそこで止まる。順番を入れ替えると、ゲストを作って
      # いないのにレート制限だけ消費してしまうため、その依存をテストで固定する。
      it "レート制限を消費しないこと" do
        expect(Users::GuestSessionsController.cache_store).not_to receive(:increment)

        post guest_sign_in_path
      end
    end

    context "すでにゲスト" do
      before { post guest_sign_in_path }

      it "ゲストを増やさないこと（既存のデモをそのまま使わせる）" do
        expect { post guest_sign_in_path }.not_to change(User.guest, :count)
      end
    end
  end

  describe "DELETE /users/sign_out（ゲストのログアウト）" do
    before { post guest_sign_in_path }

    it "トップページへ戻すこと" do
      delete destroy_user_session_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "DELETE /users/sign_out（実ユーザーのログアウト）" do
    before { sign_in create(:user) }

    it "ログイン画面へ戻すこと" do
      delete destroy_user_session_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "利用時間切れの案内" do
    # 時間切れ削除を再現する。セッションのクッキーは残したまま User だけが消える状態。
    def expire_guest
      User.guest.update_all(last_request_at: 2.hours.ago)
      GuestUserPurger.call
    end

    it "削除されたゲストがログイン画面に来たら理由を説明すること" do
      post guest_sign_in_path
      expire_guest

      get new_user_session_path

      expect(response.body).to include I18n.t("users.sessions.flash_message.guest_expired")
    end

    it "一度表示したら消えること（印を削除するため）" do
      post guest_sign_in_path
      expire_guest

      get new_user_session_path
      get new_user_session_path

      expect(response.body).not_to include I18n.t("users.sessions.flash_message.guest_expired")
    end

    it "通常のログアウト後には表示しないこと（セッションがリセットされるため）" do
      post guest_sign_in_path
      delete destroy_user_session_path

      get new_user_session_path

      expect(response.body).not_to include I18n.t("users.sessions.flash_message.guest_expired")
    end

    it "ゲストを経ていない訪問者には表示しないこと" do
      get new_user_session_path

      expect(response.body).not_to include I18n.t("users.sessions.flash_message.guest_expired")
    end
  end
end
