require "rails_helper"

RSpec.describe "Mystatuses システムテスト", type: :system do
  let(:user) { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before { sign_in user }

  describe "マイステータスページ" do
    it "タイトルとグラフ用 canvas が 2 つ表示されること" do
      visit mystatus_path

      aggregate_failures do
        expect(page).to have_content("マイステータス")
        expect(page).to have_content("光の時間")
        expect(page).to have_content("本来の自分")
        expect(page).to have_css("canvas", count: 2)
      end
    end

    it "マイページに戻るリンクからマイページへ遷移できること" do
      visit mystatus_path
      click_link "マイページに戻る"

      expect(page).to have_current_path(mypage_path)
    end
  end

  describe "マイページのハンバーガーメニューからの遷移" do
    it "「マイステータス」リンクからマイステータスページに遷移できること" do
      visit mypage_path
      # ハンバーガーメニューを開いてから遷移
      find('button[aria-label="メニュー"]').click
      click_link "マイステータス"

      expect(page).to have_current_path(mystatus_path)
    end
  end
end
