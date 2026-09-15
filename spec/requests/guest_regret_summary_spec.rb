require "rails_helper"

RSpec.describe "ゲストのAI要約表示", type: :request do
  context "ゲストのとき" do
    let(:guest) { GuestUserBuilder.call }

    before do
      sign_in guest
      get regret_records_path
    end

    it "デモ要約の本文が表示されること" do
      expect(response.body).to include(GuestDemoData.regret_summary[:content])
    end

    it "デモ用のサンプルである旨を明記すること" do
      expect(response.body).to include("デモ用のサンプル")
    end

    it "生成ボタンを出さないこと" do
      aggregate_failures do
        expect(response.body).not_to include("要約する")
        expect(response.body).not_to include(generate_regret_summary_path)
      end
    end

    it "闇の時間の特徴へ追記するボタンは出すこと（OpenAI を呼ばないため）" do
      expect(response.body).to include(append_to_dark_time_regret_summary_path)
    end
  end

  context "実ユーザーのとき" do
    let(:user) { create(:user) }

    before do
      create(:regret_record, user: user, favorited: true)
      sign_in user
      get regret_records_path
    end

    it "生成ボタンを出すこと" do
      expect(response.body).to include(generate_regret_summary_path)
    end

    it "デモ用のサンプル文言は出さないこと" do
      expect(response.body).not_to include("デモ用のサンプル")
    end
  end
end
