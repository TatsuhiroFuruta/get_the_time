require 'rails_helper'

RSpec.describe 'PurificationTimes', type: :system do
  let(:user) { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time) { create(:dark_time, user: user) }

  before { sign_in user }

  # =========================================================
  # マイページ側の浄化タイマー UI
  # =========================================================
  describe 'マイページの浄化タイマー表示' do
    context 'PurificationTime が存在しないとき(ActivityRecord 未登録)' do
      it '浄化タイマー UI が表示されないこと' do
        visit mypage_path
        expect(page).not_to have_content('浄化タイマー')
      end
    end

    context 'PurificationTime が存在するとき(ActivityRecord 登録済み)' do
      context 'remaining_time が 0 のとき (finished)' do
        let!(:purification_time) { create(:purification_time, user: user, remaining_time: 0) }

        it '「メッセージ」リンクが表示されること' do
          visit mypage_path
          aggregate_failures do
            expect(page).to have_content('浄化タイマー')
            expect(page).to have_link('メッセージ', href: purification_time_path)
            # スタート・リセットは表示されない
            expect(page).not_to have_link('スタート', href: purification_time_path)
            expect(page).not_to have_button('リセット')
          end
        end
      end

      context 'remaining_time が付与されている idle のとき' do
        let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

        it 'スタートリンクとリセットボタンが表示されること' do
          visit mypage_path
          aggregate_failures do
            expect(page).to have_content('10 分 00 秒')
            expect(page).to have_link('スタート', href: purification_time_path)
            expect(page).to have_button('リセット')
          end
        end
      end

      context 'running のとき' do
        let!(:purification_time) { create(:purification_time, :running, user: user) }

        it '「実行中」リンクが表示されること' do
          visit mypage_path
          aggregate_failures do
            expect(page).to have_link('実行中', href: purification_time_path)
            # スタートやメッセージは表示されない
            expect(page).not_to have_link('スタート', href: purification_time_path)
            expect(page).not_to have_link('メッセージ', href: purification_time_path)
          end
        end
      end

      context 'paused のとき' do
        let!(:purification_time) { create(:purification_time, :paused, user: user) }

        it 'スタートリンクとリセットボタンが表示されること' do
          visit mypage_path
          aggregate_failures do
            expect(page).to have_link('スタート', href: purification_time_path)
            expect(page).to have_button('リセット')
          end
        end
      end
    end
  end

  # =========================================================
  # 浄化タイマー詳細ページ
  # =========================================================
  describe '浄化タイマー詳細ページ' do
    context 'remaining_time が 0 のとき (finished)' do
      let!(:purification_time) { create(:purification_time, user: user, remaining_time: 0) }

      it '完了メッセージと画像が表示されること' do
        visit purification_time_path

        aggregate_failures do
          expect(page).to have_content('浄化が完了しました')
          expect(page).to have_content('また、活動時間を計測してから来てね')
          expect(page).to have_content('30分毎に10分よ')
          expect(page).to have_content('忘れないでね')
          expect(page).to have_css("img[src*='timer']")
          expect(page).to have_link('マイページに戻る', href: mypage_path)
        end
      end

      it '「マイページに戻る」を押すとマイページへ遷移すること' do
        visit purification_time_path
        click_on 'マイページに戻る'
        expect(page).to have_current_path(mypage_path)
      end
    end

    context 'idle で残り時間があるとき' do
      let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

      it 'スタートとキャンセルボタンが表示されること' do
        visit purification_time_path

        aggregate_failures do
          # display ターゲットの存在を確認(中身は JS が更新)
          expect(page).to have_css("[data-purification-timer-target='display']")
          expect(page).to have_css("img[src*='timer']")
          expect(page).to have_button('スタート')
          expect(page).to have_link('キャンセル', href: mypage_path)
        end
      end

      it 'キャンセルを押すとマイページへ遷移すること' do
        visit purification_time_path
        click_on 'キャンセル'
        expect(page).to have_current_path(mypage_path)
      end
    end

    context 'running のとき', js: true do
      let!(:purification_time) { create(:purification_time, :running, user: user) }

      it '「終了する」ボタンが表示されること' do
        visit purification_time_path
        expect(page).to have_button('終了する')
      end

      it '「終了する」を押すとマイページへ戻ること' do
        visit purification_time_path
        click_on '終了する'
        expect(page).to have_current_path(mypage_path)
      end
    end

    context 'paused のとき' do
      let!(:purification_time) { create(:purification_time, :paused, user: user) }

      it 'スタートとキャンセルボタンが表示され、他の状態の要素は出ないこと' do
        visit purification_time_path

        aggregate_failures do
          # 表示されるべき要素
          expect(page).to have_button('スタート')
          expect(page).to have_link('キャンセル', href: mypage_path)

          # 他の状態の要素は出ない
          expect(page).not_to have_button('終了する')         # running 用
          expect(page).not_to have_content('浄化が完了しました')  # finished 用
        end
      end
    end
  end

  # タイマーの動作確認は手動テストで実施

  # =========================================================
  # マイページからのフロー
  # =========================================================
  describe 'マイページから浄化タイマーを開始するフロー', js: true do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    it 'スタートリンクからスタートして実行中状態になること' do
      visit mypage_path

      # マイページの「スタート」リンクで詳細ページへ
      within('[data-controller="purification-timer"]') do
        click_on 'スタート'
      end

      # 詳細ページの「スタート」ボタンを押す
      click_on 'スタート'

      # location.reload() 後の「終了する」ボタンが表示されるのを確認
      expect(page).to have_button('終了する')
      expect(purification_time.reload).to be_running
    end
  end

  # =========================================================
  # リセット機能
  # =========================================================
  describe 'マイページのリセットボタン' do
    context 'idle 状態のとき', js: true do
      let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

      it 'confirm で OK するとリセットされること' do
        visit mypage_path

        accept_confirm('本当にタイマーをリセットしてもよろしいでしょうか？') do
          click_button 'リセット'
        end

        # reload 後、remaining_time が 0 になっている
        expect(page).to have_content('0 分 00 秒')
        expect(purification_time.reload.remaining_time).to eq 0
      end
    end

    context 'idle 状態のときに confirm でキャンセルした場合', js: true do
      let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

      it 'リセットされないこと' do
        visit mypage_path

        dismiss_confirm('本当にタイマーをリセットしてもよろしいでしょうか？') do
          click_button 'リセット'
        end

        # リセットされていないことを確認
        expect(purification_time.reload.remaining_time).to eq 600
      end
    end

    context 'running 状態のとき' do
      let!(:purification_time) { create(:purification_time, :running, user: user) }

      it 'マイページではリセットボタンが表示されないこと（実行中は「実行中」リンクのみ）' do
        visit mypage_path
        expect(page).not_to have_button('リセット')
      end
    end
  end

  # =========================================================
  # リセットボタン押下時の実行中チェック
  # =========================================================
  describe 'リセットボタン押下時の実行中チェック', js: true do
    context 'マイページ表示中にタイマーが running 状態になったとき' do
      let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

      it '「タイマー実行中です」アラートが表示されること' do
        visit mypage_path

        # 別タブ等でスタートされたシナリオを再現
        purification_time.update!(
          status: :running,
          started_at: Time.current,
          total_time: 600
        )

        accept_alert('タイマー実行中です') do
          click_button 'リセット'
        end

        # リセットが実行されていないことを確認
        expect(purification_time.reload).to be_running
      end
    end
  end
end
