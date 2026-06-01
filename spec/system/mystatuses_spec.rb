require "rails_helper"

RSpec.describe "Mystatuses システムテスト", type: :system do
  let(:user) { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before { sign_in user }

  describe "マイステータスページ" do
    it "タイトルとグラフ用 canvas が 3 つ表示されること" do
      create(:activity_record, user: user, light_time: light_time)

      visit mystatus_path

      aggregate_failures do
        expect(page).to have_content("マイステータス")
        expect(page).to have_content("光の時間")
        expect(page).to have_content("本来の自分")
        expect(page).to have_content("評価レーダー")
        expect(page).to have_content("疲労感（低いほど良い）")
        # ignore_hidden_elements = false のため、Turbo キャッシュ由来の隠れ canvas を除外して可視のみ数える
        expect(page).to have_css("canvas", count: 3, visible: true)
      end
    end

    it "マイページに戻るリンクからマイページへ遷移できること" do
      visit mystatus_path
      click_link "マイページに戻る"

      expect(page).to have_current_path(mypage_path)
    end

    it "振り返り方を見るリンクから振り返り方ページへ遷移できること" do
      visit mystatus_path
      click_link "振り返り方を見る"

      expect(page).to have_current_path(reflection_guide_path)
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
