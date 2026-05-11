require 'rails_helper'

RSpec.describe "LightTimes", type: :system do
  let(:user) { create(:user) }

  before do
    # driven_by(:rack_test)
    sign_in user
  end

  describe 'LightTime の新規作成' do
    it 'LightTime を作成できること' do
      visit new_light_time_path

      fill_in '光の時間での行動', with: '朝のヨガ'
      fill_in 'なりたい自分', with: '穏やかな自分'
      fill_in '特徴', with: 'リラックス効果'

      click_button '登録'

      expect(page).to have_content '光の時間での行動を作成しました'
      expect(page).to have_current_path(mypage_path)
    end

    it '必須項目が未入力の場合、エラーメッセージが表示されること' do
      visit new_light_time_path

      click_button '登録'

      expect(page).to have_content '光の時間での行動を作成できませんでした'
      expect(page).to have_current_path(light_times_path)
    end
  end

  describe 'LightTime の編集' do
    let!(:light_time) { create(:light_time, user: user, action: '朝のランニング', desired_self: '健康的な自分') }

    it 'LightTime を編集できること' do
      visit edit_light_time_path(light_time)

      fill_in '光の時間での行動', with: '夜のランニング'
      fill_in 'なりたい自分', with: '活力ある自分'

      click_button '更新'

      expect(page).to have_content '光の時間での行動を更新しました'
      expect(page).to have_content '夜のランニング'
    end

    it '必須項目を空にすると、エラーメッセージが表示されること' do
      visit edit_light_time_path(light_time)

      fill_in '光の時間での行動', with: ''

      click_button '更新'

      expect(page).to have_content '光の時間での行動を更新できませんでした'
    end
  end

  describe 'LightTime の削除' do
    let!(:light_time) { create(:light_time, user: user, action: '朝のランニング', is_current: true) }

    it 'LightTime を削除できること' do
      visit light_time_path(light_time)

      click_link '削除'

      expect(page).to have_content '光の時間での行動を削除しました'
      expect(page).to have_current_path(mypage_path)
    end

    context '複数の LightTime がある場合' do
      let!(:light_time1) { create(:light_time, user: user, action: '朝のヨガ', is_current: true, created_at: 2.days.ago) }
      let!(:light_time2) { create(:light_time, user: user, action: '夜の読書', is_current: false, created_at: 1.day.ago) }

      it 'current を削除すると、次の LightTime が current になること' do
        visit mypage_path

        # 現在の current は light_time1
        expect(page).to have_content '朝のヨガ'

        # light_time1 を削除
        visit light_time_path(light_time1)
        click_link '削除'

        # light_time2 が current になっている
        expect(light_time2.reload.is_current).to be true
      end
    end
  end

  describe 'LightTime の詳細表示' do
    let!(:light_time) { create(:light_time, user: user, action: '朝のヨガ', desired_self: '穏やかな自分', characteristic: 'リラックス効果') }

    it 'LightTime の詳細が表示されること' do
      visit light_time_path(light_time)

      expect(page).to have_content '朝のヨガ'
      expect(page).to have_content '穏やかな自分'
      expect(page).to have_content 'リラックス効果'
    end
  end

  describe 'マイページでの LightTime 表示' do
    context 'LightTime が登録されている場合' do
      let!(:light_time) { create(:light_time, user: user, action: '朝のヨガ', desired_self: '穏やかな自分', is_current: true) }

      it 'current な LightTime が表示されること' do
        visit mypage_path

        expect(page).to have_content '朝のヨガ'
        expect(page).to have_content '穏やかな自分'
      end
    end

    context 'LightTime が登録されていない場合' do
      it '新規登録を促すメッセージが表示されること' do
        visit mypage_path

        expect(page).to have_content '光の時間での行動が'
        expect(page).to have_content '登録されていません'
        expect(page).to have_link '新規登録', href: new_light_time_path
      end
    end

    context '複数の LightTime がある場合' do
      let!(:light_time1) { create(:light_time, user: user, action: '朝のヨガ', is_current: true, created_at: 2.days.ago) }
      let!(:light_time2) { create(:light_time, user: user, action: '夜の読書', is_current: false, created_at: 1.day.ago) }

      it '切り替えボタンが表示されること' do
        visit mypage_path

        expect(page).to have_button '<'
        expect(page).to have_button '>'
      end
    end

    context 'LightTime が1件のみの場合' do
      let!(:light_time) { create(:light_time, user: user, action: '朝のヨガ', is_current: true) }

      it '切り替えボタンが表示されないこと' do
        visit mypage_path

        expect(page).not_to have_button '<'
        expect(page).not_to have_button '>'
      end
    end
  end
end
