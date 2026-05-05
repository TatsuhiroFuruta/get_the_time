require 'rails_helper'

RSpec.describe "Users", type: :request do
  let!(:user) { create(:user) }

  describe "GET /mypage" do
    context "未ログイン" do
      it "ログイン画面にリダイレクトされる" do
        get mypage_path

        expect(response).to redirect_to(new_user_session_path)

        follow_redirect!
        expect(response.body).to include(
          I18n.t("devise.failure.unauthenticated")
        )
      end
    end

    context "ログイン済み" do
      it "アクセスできる" do
        sign_in user

        get mypage_path

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /users/sign_in" do
    context "ログイン済み" do
      it "rootにリダイレクトされる" do
        sign_in user

        get new_user_session_path

        expect(response).to redirect_to(root_path)

        follow_redirect!
        expect(response.body).to include(
          I18n.t("devise.failure.already_authenticated")
        )
      end
    end
  end
end
