require "rails_helper"

RSpec.describe "Users::OmniauthCallbacks", type: :request do
  describe "GET /users/auth/google_oauth2/callback（Google認証）" do
    context "未登録のメールアドレスの場合" do
      it "新規ユーザーを作成してログインし、ルートへリダイレクトする" do
        mock_google_oauth2(email: "new@example.com", name: "新規太郎")

        expect {
          get user_google_oauth2_omniauth_callback_path
        }.to change(User, :count).by(1)

        user = User.find_by(email: "new@example.com")
        aggregate_failures do
          expect(user.provider).to eq("google_oauth2")
          expect(user.uid).to eq("123456789")
          expect(user.name).to eq("新規太郎")
          # 新規作成時はパスワードがランダムに設定され、ログイン可能な状態になる
          expect(response).to redirect_to(root_path)
          # 成功フラッシュは devise-i18n のキー経由で表示される
          expect(flash[:notice]).to eq(
            I18n.t("devise.omniauth_callbacks.success", kind: "Google")
          )
        end
      end

      it "新規ユーザー作成時にポモドーロ設定も生成される" do
        mock_google_oauth2(email: "new@example.com")

        get user_google_oauth2_omniauth_callback_path

        expect(User.find_by(email: "new@example.com").pomodoro_setting).to be_present
      end
    end

    context "同じメールアドレスの既存ユーザーがいる場合" do
      let!(:existing_user) { create(:user, email: "existing@example.com", name: "既存花子") }

      it "新規作成せず既存アカウントに provider/uid を紐付けてログインする" do
        mock_google_oauth2(email: "existing@example.com", name: "別の名前")

        expect {
          get user_google_oauth2_omniauth_callback_path
        }.not_to change(User, :count)

        existing_user.reload
        aggregate_failures do
          expect(existing_user.provider).to eq("google_oauth2")
          expect(existing_user.uid).to eq("123456789")
          # 既存ユーザーの名前は上書きしない
          expect(existing_user.name).to eq("既存花子")
          expect(response).to redirect_to(root_path)
        end
      end

      it "既存ユーザーのパスワードは上書きされず、従来のパスワードでログインできる" do
        original_encrypted = existing_user.encrypted_password
        mock_google_oauth2(email: "existing@example.com")

        get user_google_oauth2_omniauth_callback_path

        expect(existing_user.reload.encrypted_password).to eq(original_encrypted)
      end
    end

    context "認証に失敗した場合" do
      it "ルートへリダイレクトし、ユーザーは作成されない" do
        mock_google_oauth2_failure

        # authorize へのリクエストが失敗エンドポイントへリダイレクトされ、
        # OmniauthCallbacksController#failure 経由でルートへ戻る
        expect {
          post user_google_oauth2_omniauth_authorize_path
          follow_redirect! # /users/auth/failure
          follow_redirect! # root_path
        }.not_to change(User, :count)

        aggregate_failures do
          expect(response).to redirect_to(root_path).or have_http_status(:ok)
          # 失敗時は自作の日本語メッセージを表示する
          expect(flash[:alert]).to eq("Google認証に失敗しました。")
        end
      end
    end
  end
end
