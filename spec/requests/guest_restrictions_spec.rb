require "rails_helper"

RSpec.describe "ゲストへの操作制限", type: :request do
  let(:guest) { GuestUserBuilder.call }
  let(:message) { I18n.t("defaults.flash_message.guest_not_allowed") }

  before { sign_in guest }

  # UI からリンクを消すだけではルートが残るため、サーバ側で塞げていることを直接叩いて確認する。
  shared_examples "ゲストを拒否する" do
    it "マイページへリダイレクトし、理由を表示すること" do
      request_action

      aggregate_failures do
        expect(response).to redirect_to(mypage_path)
        expect(flash[:alert]).to eq message
      end
    end
  end

  describe "GET /users/edit（アカウント編集）" do
    def request_action = get edit_user_registration_path

    include_examples "ゲストを拒否する"
  end

  describe "PUT /users（アカウント更新）" do
    def request_action = put user_registration_path, params: { user: { name: "変更後" } }

    include_examples "ゲストを拒否する"

    it "名前が変わらないこと" do
      expect { request_action }.not_to change { guest.reload.name }
    end
  end

  describe "DELETE /users（アカウント削除）" do
    def request_action = delete user_registration_path

    include_examples "ゲストを拒否する"

    it "ユーザーが残ること" do
      request_action

      expect(User.exists?(guest.id)).to be true
    end
  end

  # ゲストのメールは架空アドレスで届かないため、再設定画面には到達させない。
  # ただし塞いでいるのは reject_guest ではなく Devise の require_no_authentication で、
  # そちらが prepend_before_action で先に走る。文言が異なるのはそのため。
  describe "GET /users/password/new（パスワード再設定）" do
    # 遷移先が root_path なのは、認証済みルートの名前が user_root ではなく
    # authenticated_root のため Devise の signed_in_root_path が root_path に落ちるから。
    # ログイン中に / を開けば authenticated 制約でマイページが描画される。
    it "再設定画面には入れず追い返されること" do
      get new_user_password_path

      aggregate_failures do
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq I18n.t("devise.failure.already_authenticated")
      end
    end
  end

  describe "PATCH /regret_summary/generate（AI要約の生成）" do
    def request_action = patch generate_regret_summary_path

    include_examples "ゲストを拒否する"

    it "OpenAI を呼ばないこと" do
      expect(RegretSummarizer).not_to receive(:new)

      request_action
    end
  end

  describe "制限していない操作" do
    it "アカウント情報画面は見られること（guest_ のメールが使い捨てであることを伝えるため）" do
      get user_account_path

      expect(response).to have_http_status(:ok)
    end

    it "ただしアカウント情報画面に編集ボタンは出さないこと" do
      get user_account_path

      expect(response.body).not_to include(edit_user_registration_path)
    end

    it "闇の時間の特徴への追記はできること（OpenAI を呼ばないため）" do
      patch append_to_dark_time_regret_summary_path

      expect(flash[:alert]).not_to eq message
    end

    it "後悔記録は作成できること" do
      expect {
        post regret_records_path, params: { regret_record: { content: "テスト" } }
      }.to change(guest.regret_records, :count).by(1)
    end
  end

  describe "実ユーザーのとき" do
    let(:real_user) { create(:user) }

    before { sign_in real_user }

    it "アカウント編集が通ること" do
      get edit_user_registration_path

      expect(response).to have_http_status(:ok)
    end
  end
end
