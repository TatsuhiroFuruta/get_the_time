require 'rails_helper'

RSpec.describe "LightTime Switch", type: :system, js: true do
  let(:user) { create(:user) }
  let!(:light_time1) { create(:light_time, user: user, action: '朝のヨガ', is_current: true, created_at: 3.days.ago) }
  let!(:light_time2) { create(:light_time, user: user, action: '夜の読書', is_current: false, created_at: 2.days.ago) }
  let!(:light_time3) { create(:light_time, user: user, action: '昼の瞑想', is_current: false, created_at: 1.day.ago) }

  before do
    # driven_by(:selenium_chrome_headless)
    sign_in user
  end

  describe '画面切り替え機能' do
    context 'ボタンクリックによる切り替え' do
      it '次へボタンで次の LightTime に切り替わること' do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 次へボタンをクリック
        find('button', text: '>').click

        # Turbo Stream のレスポンスを待つ
        sleep 0.5

        expect(page).to have_content '夜の読書'
      end

      it '前へボタンで前の LightTime に切り替わること' do
        # light_time2 を current にする
        LightTime.switch_current!(user, light_time2)

        visit mypage_path

        expect(page).to have_content '夜の読書'

        # 前へボタンをクリック
        find('button', text: '<').click

        sleep 0.5

        expect(page).to have_content '朝のヨガ'
      end

      it '最初の LightTime で前へボタンを押しても変わらないこと' do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 前へボタンをクリック（最初なので変わらない）
        find('button', text: '<').click

        sleep 0.5

        expect(page).to have_content '朝のヨガ'
      end

      it '最後の LightTime で次へボタンを押しても変わらないこと' do
        # light_time3 を current にする
        LightTime.switch_current!(user, light_time3)

        visit mypage_path

        expect(page).to have_content '昼の瞑想'

        # 次へボタンをクリック（最後なので変わらない）
        find('button', text: '>').click

        sleep 0.5

        expect(page).to have_content '昼の瞑想'
      end

      it '連続して切り替えができること' do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 次へボタンを2回クリック
        find('button', text: '>').click
        sleep 0.5
        expect(page).to have_content '夜の読書'

        find('button', text: '>').click
        sleep 0.5
        expect(page).to have_content '昼の瞑想'
      end
    end

    context 'キーボード操作による切り替え（デスクトップ）' do
      before do
        # デスクトップサイズに設定
        page.driver.browser.manage.window.resize_to(1024, 768)
      end

      it '下矢印キーで次の LightTime に切り替わること', js: true do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 下矢印キーを送信
        find('body').send_keys(:arrow_down)

        sleep 0.5

        expect(page).to have_content '夜の読書'
      end

      it '上矢印キーで前の LightTime に切り替わること', js: true do
        LightTime.switch_current!(user, light_time2)

        visit mypage_path

        expect(page).to have_content '夜の読書'

        # 上矢印キーを送信
        find('body').send_keys(:arrow_up)

        sleep 0.5

        expect(page).to have_content '朝のヨガ'
      end

      it '左右の矢印キーでは切り替わらないこと', js: true do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 右矢印キーを送信（デスクトップでは無効）
        find('body').send_keys(:arrow_right)

        sleep 0.5

        expect(page).to have_content '朝のヨガ'
      end
    end

    context 'キーボード操作による切り替え（モバイル）' do
      before do
        # モバイルサイズに設定
        page.driver.browser.manage.window.resize_to(375, 667)
      end

      it '右矢印キーで次の LightTime に切り替わること', js: true do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 右矢印キーを送信
        find('body').send_keys(:arrow_right)

        sleep 0.5

        expect(page).to have_content '夜の読書'
      end

      it '左矢印キーで前の LightTime に切り替わること', js: true do
        LightTime.switch_current!(user, light_time2)

        visit mypage_path

        expect(page).to have_content '夜の読書'

        # 左矢印キーを送信
        find('body').send_keys(:arrow_left)

        sleep 0.5

        expect(page).to have_content '朝のヨガ'
      end

      it '上下の矢印キーでは切り替わらないこと', js: true do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 下矢印キーを送信（モバイルでは無効）
        find('body').send_keys(:arrow_down)

        sleep 0.5

        expect(page).to have_content '朝のヨガ'
      end
    end

    context 'LightTime が1件のみの場合' do
      let(:user_with_one) { create(:user) }
      let!(:only_light_time) { create(:light_time, user: user_with_one, action: '唯一の習慣', is_current: true) }

      before do
        sign_in user_with_one
      end

      it '切り替えボタンが表示されないこと' do
        visit mypage_path

        expect(page).not_to have_button '<'
        expect(page).not_to have_button '>'
      end

      it 'キーボード操作しても切り替わらないこと', js: true do
        visit mypage_path

        expect(page).to have_content '唯一の習慣'

        # 矢印キーを送信
        find('body').send_keys(:arrow_down)

        sleep 0.5

        # 変わらない
        expect(page).to have_content '唯一の習慣'
      end
    end

    context 'Turbo Stream のレスポンス' do
      it 'ページ全体がリロードされないこと', js: true do
        visit mypage_path

        # ページに一意のIDを追加
        page.execute_script("document.body.setAttribute('data-test-id', 'original-page')")

        # 次へボタンをクリック
        find('button', text: '>').click

        sleep 0.5

        # ページがリロードされていないことを確認
        expect(page).to have_css('body[data-test-id="original-page"]')
      end

      it 'LightTime の内容だけが更新されること', js: true do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'

        # 次へボタンをクリック
        find('button', text: '>').click

        sleep 0.5

        # 内容が更新されている
        expect(page).to have_content '夜の読書'
        expect(page).not_to have_content '朝のヨガ'
      end
    end
  end
end
