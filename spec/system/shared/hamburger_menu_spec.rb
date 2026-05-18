require 'rails_helper'

RSpec.describe 'ハンバーガーメニュー', type: :system do
  let(:user) { create(:user) }
  # ハンバーガーメニューはマイページに dark_time と light_time の両方がある時のみ表示される
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before do
    sign_in user
    visit mypage_path
  end

  describe '開閉動作' do
    it '初期状態ではメニューが閉じていること' do
      # メニューは translate-x-full で画面外に隠されている
      expect(page).to have_selector('[data-hamburger-target="menu"].-translate-x-full')
    end

    context 'ハンバーガーボタンをクリックしたとき' do
      it 'メニューが開くこと' do
        find('[data-hamburger-target="button"]').click
        # 開いた後は -translate-x-full クラスが外れる
        expect(page).not_to have_selector('[data-hamburger-target="menu"].-translate-x-full', wait: 5)
      end

      it 'オーバーレイが表示されること' do
        find('[data-hamburger-target="button"]').click
        expect(page).to have_selector('[data-hamburger-target="overlay"]:not(.hidden)', wait: 5)
      end
    end

    context 'メニューが開いているときにハンバーガーボタンを再度クリックしたとき' do
      before { find('[data-hamburger-target="button"]').click }

      it 'メニューが閉じること' do
        # 一度開いた状態を確認してから再クリック
        expect(page).not_to have_selector('[data-hamburger-target="menu"].-translate-x-full', wait: 5)

        find('[data-hamburger-target="button"]').click

        aggregate_failures do
          expect(page).to have_selector('[data-hamburger-target="menu"].-translate-x-full', wait: 5)
          expect(page).to have_selector('[data-hamburger-target="overlay"].hidden', wait: 5)
        end
      end
    end

    context 'オーバーレイをクリックしたとき' do
      before { find('[data-hamburger-target="button"]').click }

      it 'メニューが閉じること' do
        find('[data-hamburger-target="overlay"]').click
        expect(page).to have_selector('[data-hamburger-target="menu"].-translate-x-full', wait: 5)
      end
    end
  end

  describe 'メニュー内のリンク' do
    before { find('[data-hamburger-target="button"]').click }

    it '「マイページ」リンクをクリックするとマイページへ遷移すること' do
      within('[data-hamburger-target="menu"]') do
        click_on 'マイページ'
      end
      expect(page).to have_current_path(mypage_path)
    end

    it '「活動記録」リンクをクリックすると一覧ページへ遷移すること' do
      within('[data-hamburger-target="menu"]') do
        click_on '活動記録'
      end
      expect(page).to have_current_path(activity_records_path)
    end
  end
end
