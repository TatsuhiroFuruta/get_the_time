require "rails_helper"

RSpec.describe "StaticPages", type: :request do
  describe "GET / (home)" do
    it "200 が返り、SNS シェア用の OGP メタタグが描画されること" do
      get root_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(name="twitter:card" content="summary_large_image"))
        expect(response.body).to match(%r{property="og:image" content="[^"]*ogp[^"]*"})
      end
    end

    it "content_for 未設定のとき og:title / og:description に既定値が入ること" do
      get root_path

      aggregate_failures do
        expect(response.body).to include(%(property="og:title" content="Get The Time"))
        expect(response.body).to include("自由時間を「光の時間」と「闇の時間」に分け、本来の自分を計測するサービス")
      end
    end

    # rails new のデフォルト値 "Myapp" がサイト名メタに混入した不具合の回帰ガード。
    # サイト名・紹介文は ApplicationHelper の定数に集約されている。
    it "サイト名メタが SITE_TITLE で出力され、デフォルト値 Myapp が残っていないこと" do
      get root_path

      aggregate_failures do
        expect(response.body).to include(%(<meta name="application-name" content="#{ApplicationHelper::SITE_TITLE}">))
        expect(response.body).to include(%(<meta property="og:site_name" content="#{ApplicationHelper::SITE_TITLE}">))
        expect(response.body).not_to include("Myapp")
      end
    end
  end

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

  describe "GET /terms（利用規約）" do
    it "未ログインでも 200 が返り、主要な条項が表示されること" do
      get terms_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("利用規約")
        expect(response.body).to include("第6条（禁止事項）")
        expect(response.body).to include("第16条（準拠法・裁判管轄）")
      end
    end
  end

  describe "GET /privacy（プライバシーポリシー）" do
    it "未ログインでも 200 が返り、主要な条項が表示されること" do
      get privacy_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("プライバシーポリシー")
        expect(response.body).to include("第6条（外部サービスへの取り扱いの委託）")
        expect(response.body).to include("OpenAI, L.L.C.")
      end
    end
  end
end
