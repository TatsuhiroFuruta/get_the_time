require "rails_helper"

RSpec.describe "StaticPages", type: :request do
  describe "GET /reflection_guide" do
    context "ログイン済みのとき" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "200 が返り、振り返り方の見出しと各評価項目が表示されること" do
        get reflection_guide_path

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("振り返り方")
          expect(response.body).to include("満足度")
          expect(response.body).to include("進行度")
          expect(response.body).to include("作業の質")
          expect(response.body).to include("集中度")
          expect(response.body).to include("疲労感")
        end
      end
    end

    context "未ログインのとき" do
      it "ログインページへリダイレクトされること" do
        get reflection_guide_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
