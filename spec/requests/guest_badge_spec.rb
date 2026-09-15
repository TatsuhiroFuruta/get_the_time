require "rails_helper"

RSpec.describe "ゲスト利用中バッジ", type: :request do
  context "ゲストのとき" do
    let(:guest) { GuestUserBuilder.call }

    before { sign_in guest }

    # _hamburger_menu は4画面でしか描画されないため、レイアウトに置いて全画面で出す。
    it "マイページで表示されること" do
      get mypage_path

      expect(response.body).to include("ゲスト利用中")
    end

    it "ハンバーガーメニューの無いフォーム画面でも表示されること" do
      get new_light_time_path

      expect(response.body).to include("ゲスト利用中")
    end

    it "登録への導線は置かないこと（データが引き継がれると誤解させないため）" do
      get mypage_path

      expect(response.body).not_to include(new_user_registration_path)
    end
  end

  context "実ユーザーのとき" do
    before { sign_in create(:user) }

    it "表示しないこと" do
      get mypage_path

      expect(response.body).not_to include("ゲスト利用中")
    end
  end

  context "未ログインのとき" do
    it "表示しないこと" do
      get root_path

      expect(response.body).not_to include("ゲスト利用中")
    end
  end
end
