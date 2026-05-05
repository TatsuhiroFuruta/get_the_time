require 'rails_helper'

RSpec.describe "User Sessions", type: :request do
  let!(:user) { create(:user) }

  describe "POST /users/sign_in" do
    context "正常系" do
      it "ログインできる" do
        post user_session_path, params: {
          user: {
            email: user.email,
            password: "password123"
          }
        }

        expect(response).to redirect_to(root_path)
      end
    end

    context "異常系" do
      it "ログイン失敗する" do
        post user_session_path, params: {
          user: {
            email: user.email,
            password: "wrong_password"
          }
        }

        expect(response.body).to include("メールアドレスまたはパスワードが違います。")
      end
    end
  end

  describe "DELETE /users/sign_out" do
    it "ログアウトできる" do
      sign_in user

      delete destroy_user_session_path

      # 1. リダイレクトの指示が来ているか確認 (303)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(new_user_session_path)

      # 2. 指示に従って次のページへ移動する
      follow_redirect!
      # 3. 移動後のページで「ログアウトしました」という文字を探す
      expect(response.body).to include(
        I18n.t("devise.sessions.signed_out")
      )
    end
  end
end
