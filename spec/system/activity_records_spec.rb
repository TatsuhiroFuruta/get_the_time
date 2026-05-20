require 'rails_helper'

RSpec.describe 'ActivityRecords システムテスト', type: :system do
  let(:user) { create(:user) }
  # 固定文言「朝のランニング」「夜更かししてしまう」をそのまま使う
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before do
    sign_in user
  end

  describe 'マイページからポモドーロタイマー画面への遷移' do
    it '「やること」を入力してスタートすると入力内容が引き継がれること' do
      visit mypage_path
      fill_in 'やることを入力', with: 'マイページからのタスク'
      click_on 'スタート'

      aggregate_failures do
        expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)
        expect(page).to have_content('マイページからのタスク')
      end
    end

    it '「やること」未入力でスタートしてもポモドーロタイマー画面に遷移できること' do
      visit mypage_path
      # やることを入力せずにスタート
      click_on 'スタート'

      aggregate_failures do
        expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)
        # タイマー画面の主要要素が表示される
        expect(page).to have_content('25:00')
        expect(page).to have_content('朝のランニング')
        expect(page).to have_content('健康的な自分')
      end
    end
  end

  # =========================================================
  # ポモドーロタイマー画面
  # =========================================================
  describe 'ポモドーロタイマー画面' do
    before { visit pomodoro_timer_activity_records_path }

    it 'タイマー画面が表示されること' do
      aggregate_failures do
        expect(page).to have_content('25:00')
        expect(page).to have_content('朝のランニング')
        expect(page).to have_content('健康的な自分')
      end
    end

    it 'スタートボタンと終了するボタンが表示されること' do
      aggregate_failures do
        expect(page).to have_button('スタート')
        expect(page).to have_button('終了する')
      end
    end

    it 'スタートせずに「終了する」をクリックするとアラートが表示されること' do
      accept_alert('スタートボタンを押してください') do
        click_on '終了する', visible: true
      end
    end

    it '「集中できない、やる気が出ないときは」をクリックするとモチベーション画面が表示されること' do
      click_on '集中できない、やる気が出ないときは', visible: true
      expect(page).to have_selector('[data-pomodoro-target="motivationScreen"]:not(.hidden)')
      expect(page).to have_selector('[data-pomodoro-target="workScreen"].hidden')
      expect(page).to have_content('夜更かししてしまう')
      expect(page).to have_content('健康を損なう')
    end

    it 'モチベーション画面で「いいえ、もう少し頑張ります！」をクリックすると作業画面に戻ること' do
      click_on '集中できない、やる気が出ないときは', visible: true
      click_on 'いいえ、もう少し頑張ります！'
      expect(page).to have_selector('[data-pomodoro-target="workScreen"]:not(.hidden)')
      expect(page).to have_selector('[data-pomodoro-target="motivationScreen"].hidden')
      expect(page).to have_content('25:00')
      expect(page).to have_button('スタート')
    end

    context 'やること入力フォームに入力して「更新する」をクリックしたとき' do
      it 'やること表示エリアが入力内容に更新されること' do
        fill_in 'やることを入力', with: '今日のタスク'
        click_on '更新する'
        expect(page).to have_content('今日のタスク')
      end
    end
  end

  # =========================================================
  # ポモドーロタイマー動作中
  # =========================================================
  describe 'ポモドーロタイマー動作中' do
    before do
      visit pomodoro_timer_activity_records_path
      # Stimulus の value を直接書き換えてタイマーを短縮
      # work: 3秒、break: 2秒 に設定
      page.execute_script(<<~JS)
        const el = document.querySelector('[data-controller="pomodoro"]')
        el.dataset.pomodoroWorkDurationValue = 3
        el.dataset.pomodoroBreakDurationValue = 2
      JS
    end

    context 'スタートボタンをクリックしたとき' do
      it 'スタートボタンが非表示になりタイマーが動き始めること' do
        click_on 'スタート', visible: true
        aggregate_failures do
          expect(page).not_to have_button('スタート', visible: true)
          expect(page).to have_content('00:02', wait: 3)
        end
      end
    end

    context '作業時間が終了したとき' do
      it '休憩画面に切り替わりポモドーロ数が1になること' do
        click_on 'スタート', visible: true

        aggregate_failures do
          # 1. 休憩画面（breakScreenターゲット）が目に見える状態になっていること
          expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)

          # 2. 作業画面（workScreenターゲット）が非表示になっていること
          expect(page).to have_selector('[data-pomodoro-target="workScreen"].hidden')

          # 3. ポモドーロ数のカウントアップを確認
          expect(page).to have_content('ポモドーロ数：1', wait: 10)

          # 4. 休憩画面の中身を網羅的に検証
          within('[data-pomodoro-target="breakScreen"]') do
            expect(page).to have_css('img[src*="timer"]') # timer.png があるか
            expect(page).to have_button('集中できない、やる気が出ないときは', visible: true)
            expect(page).to have_button('終了する', visible: true)
          end
        end
      end
    end

    context '休憩時間が終了したとき' do
      it '作業画面に戻りスタートボタンが表示されること' do
        click_on 'スタート', visible: true
        aggregate_failures do
          # 作業3秒 + 休憩2秒 終了後にスタートボタンが再表示される
          expect(page).to have_button('スタート', wait: 15)
          expect(page).to have_content('ポモドーロ数：1', wait: 15)
        end
      end
    end

    # =========================================================
    # 無操作タイムアウト（2回目以降のセッション）
    # =========================================================
    context '2回目以降のセッションで無操作タイムアウトが発生したとき' do
      before do
        # 無操作タイムアウトも短縮（2秒）、チェック間隔も短縮（0.5秒）
        page.execute_script(<<~JS)
          const el = document.querySelector('[data-controller="pomodoro"]')
          const controller = window.Stimulus.getControllerForElementAndIdentifier(el, 'pomodoro')
          controller.inactivityTimeout = 2000  // タイムアウト2秒
          controller.checkInterval = 500       // 0.5秒ごとにチェック
        JS

        # 1回目のポモドーロを完了させて休憩画面へ
        click_on 'スタート', visible: true

        # 作業時間（3秒）終了を待つ → 休憩画面へ切り替わる
        expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)
        # 休憩時間（2秒）終了を待つ → 作業画面に戻りスタートボタンが表示される
        expect(page).to have_button('スタート', wait: 10)
        # この時点で inactivityCheck が開始されている
      end

      it '無操作タイムアウト後に自動で新規作成画面へ遷移すること' do
        accept_alert(wait: 10)
        expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
      end
      # ✕ テストせず目視で確認する：タイムアウト時間の正確性（20分かどうか）
      # 手動の動作確認で担保
    end

    # =========================================================
    # 終了ボタン後に新規作成画面へ遷移
    # =========================================================
    describe '終了ボタンをクリックしたとき' do
      before do
        visit pomodoro_timer_activity_records_path
        # Stimulus の value を直接書き換えてタイマーを短縮
        # work: 3秒、break: 2秒 に設定
        page.execute_script(<<~JS)
          const el = document.querySelector('[data-controller="pomodoro"]')
          el.dataset.pomodoroWorkDurationValue = 3
          el.dataset.pomodoroBreakDurationValue = 2
        JS
      end

      context '作業画面から終了したとき' do
        it 'スタート後に終了すると新規作成画面へ遷移すること' do
          click_on 'スタート', visible: true
          # スタート直後はタイマーが動いているので startButton が hidden になることを確認
          expect(page).to have_selector('[data-pomodoro-target="startButton"].hidden', wait: 5)

          # 作業画面の終了ボタンを直接クリック（アラートは出ない）
          within('[data-pomodoro-target="workScreen"]') do
            click_on '終了する', visible: true
          end

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end
      end

      context '休憩画面から終了したとき' do
        before do
          click_on 'スタート', visible: true
          # 作業時間終了を待つ → 休憩画面へ
          expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)
        end

        it '新規作成画面へ遷移すること' do
          within('[data-pomodoro-target="breakScreen"]') do
            click_on '終了する', visible: true
          end

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end
      end

      context 'モチベーション画面の「それでいいもん」をクリックしたとき' do
        before do
          click_on 'スタート', visible: true
          within('[data-pomodoro-target="workScreen"]') do
            click_on '集中できない、やる気が出ないときは', visible: true
          end
          expect(page).to have_selector('[data-pomodoro-target="motivationScreen"]:not(.hidden)', wait: 5)
        end

        it '新規作成画面へ遷移すること' do
          click_on 'それでいいもん'

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end
      end
    end
  end

  # =========================================================
  # 登録フロー (new → create)
  # =========================================================
  describe '登録フロー' do
    let(:form_params) do
      {
        activity_record_form: {
          started_at:     1.hour.ago.iso8601,
          ended_at:       Time.current.iso8601,
          total_duration: 60,
          task:           'システムテストタスク',
          light_time_id:  light_time.id
        }
      }
    end

    before { visit new_activity_record_path(form_params) }

    it '登録フォームが表示されること' do
      aggregate_failures do
        expect(page).to have_content('光の時間の活動記録登録')
        expect(page).to have_content('朝のランニング')
        expect(page).to have_content('60')
      end
    end

    context '評価項目をすべて選択して「記録する」をクリックしたとき' do
      it '一覧ページへ遷移し、フラッシュメッセージが表示されること' do
        # rating_field ヘルパーが生成するラジオボタンを選択（value="3"）
        %w[satisfaction progress quality focus fatigue].each do |attr|
          find("input[name='activity_record_form[#{attr}]'][value='3']").choose
        end

        click_on '記録する'

        expect(page).to have_current_path(activity_records_path)
        expect(page).to have_content(
          I18n.t('defaults.flash_message.created', item: ActivityRecordForm.model_name.human)
        )
      end

      it '浄化タイマー獲得モーダルが表示され、OKをクリックすると閉じること' do
        %w[satisfaction progress quality focus fatigue].each do |attr|
          find("input[name='activity_record_form[#{attr}]'][value='3']").choose
        end

        click_on '記録する'

        # モーダルが表示されている
        # total_duration: 60 → (60/30).floor * 10 = 20分付与
        expect(page).to have_content('浄化タイマーを20分獲得！')

        # OKボタンをクリックするとモーダルが閉じる
        click_on 'OK'

        # closeアクションで display:none になるまで待つ（setTimeoutで300ms）
        expect(page).to have_selector('[data-controller="modal"]', visible: :hidden, wait: 5)
      end
    end

    context 'total_duration が 30分未満で記録したとき' do
      let(:form_params) do
        {
          activity_record_form: {
            started_at:     1.hour.ago.iso8601,
            ended_at:       Time.current.iso8601,
            total_duration: 20,  # ← 30分未満
            task:           'システムテストタスク',
            light_time_id:  light_time.id
          }
        }
      end

      it '浄化タイマー獲得モーダルが表示されないこと' do
        %w[satisfaction progress quality focus fatigue].each do |attr|
          find("input[name='activity_record_form[#{attr}]'][value='3']").choose
        end

        click_on '記録する'

        aggregate_failures do
          expect(page).to have_current_path(activity_records_path)
          # モーダルのテキストが表示されないこと
          expect(page).not_to have_content('浄化タイマーを')
          expect(page).not_to have_content('獲得！')
        end
      end
    end

    context '評価項目を未選択のまま「記録する」をクリックしたとき' do
      it 'エラーメッセージとフラッシュメッセージが表示されること' do
        click_on '記録する'

        aggregate_failures do
          # 各評価項目のエラーメッセージ
          %w[satisfaction progress quality focus fatigue].each do |attr|
            expect(page).to have_content('について、1から5のいずれかを選択してください')
          end

          # フラッシュメッセージ
          expect(page).to have_content(
            I18n.t('defaults.flash_message.not_created', item: ActivityRecordForm.model_name.human)
          )

          # 登録フォームに留まっていること
          expect(page).to have_current_path(new_activity_record_path, ignore_query: true)
        end
      end
    end

    it '「記録しない」をクリックするとマイページへ遷移すること' do
      click_on '記録しない'
      expect(page).to have_current_path(mypage_path)
    end
  end

  # =========================================================
  # 一覧画面 (index)
  # =========================================================
  describe '一覧画面' do
    context '活動記録がないとき' do
      it '未登録メッセージが表示されること' do
        visit activity_records_path
        expect(page).to have_content('光の時間の活動記録が登録されていません')
      end
    end

    context '活動記録があるとき' do
      let!(:activity_record) do
        create(:activity_record, user: user, light_time: light_time, comment: '集中できた日')
      end

      it '光の時間の活動内容とコメントが一覧に表示されること' do
        visit activity_records_path
        expect(page).to have_content('朝のランニング')
        expect(page).to have_content('集中できた日')
      end

      it 'レコードをクリックすると詳細ページへ遷移すること' do
        visit activity_records_path
        find('a', text: '朝のランニング').click
        expect(page).to have_current_path(activity_record_path(activity_record))
      end
    end

    context '検索フォームを使ったとき' do
      before do
        create(:activity_record, user: user, light_time: light_time, comment: '検索ヒット')
        create(:activity_record, user: user, light_time: light_time, comment: '対象外')
      end

      it '検索ワードに一致するレコードだけ表示されること' do
        visit activity_records_path
        fill_in 'コメント or 活動内容で検索', with: '検索ヒット'
        click_on '検索'
        expect(page).to have_content('検索ヒット')
        expect(page).not_to have_content('対象外')
      end

      it '一致しないワードのとき「検索結果が見つかりませんでした」と表示されること' do
        visit activity_records_path
        fill_in 'コメント or 活動内容で検索', with: '存在しないキーワード'
        click_on '検索'
        expect(page).to have_content('検索結果が見つかりませんでした')
      end
    end
  end

  # =========================================================
  # 一覧画面（ページネーション）
  # =========================================================
  describe '一覧画面（ページネーション）' do
    context '活動記録が9件以上あるとき' do
      before do
        # 9件作成（per_page: 8 を超える件数）
        9.times do |i|
          create(:activity_record, user: user, light_time: light_time, comment: "コメント#{i + 1}")
        end
        visit activity_records_path
      end

      it '1ページ目には8件まで表示されること' do
        # 9件のうち8件のみ表示
        within('div.space-y-4') do
          expect(page).to have_selector('.bg-amber-500', count: 8)
        end
      end

      it 'ページネーションリンクが表示されること' do
        expect(page).to have_selector('[data-test="pagination"]')
      end

      it '2ページ目をクリックすると残りのレコードが表示されること' do
        click_on '2'

        aggregate_failures do
          expect(page).to have_current_path(activity_records_path, ignore_query: true)
          # 9件目（=最も古いレコード）が表示される
          # created_at: desc 順なので、最初に作ったレコード = 「コメント1」が2ページ目に来る
          expect(page).to have_content('コメント1')
        end
      end
    end

    context '活動記録が8件以下のとき' do
      before do
        create(:activity_record, user: user, light_time: light_time)
        visit activity_records_path
      end

      it 'ページネーションリンクが表示されないこと' do
        expect(page).not_to have_selector('[data-test="pagination"]')
      end
    end
  end

  # =========================================================
  # 詳細画面 (show)
  # =========================================================
  describe '詳細画面' do
    let!(:activity_record) do
      create(:activity_record, :high_rating,
             user: user, light_time: light_time,
             task: '詳細確認タスク', comment: '詳細コメント',
             total_duration: 60, idle_duration: 5)
    end

    before { visit activity_record_path(activity_record) }

    it '各項目が表示されること' do
      aggregate_failures do
        expect(page).to have_content('朝のランニング')
        expect(page).to have_content('詳細確認タスク')
        expect(page).to have_content('詳細コメント')
        expect(page).to have_content('60')
        expect(page).to have_content('5')
      end
    end

    it '「編集」リンクが表示されること' do
      expect(page).to have_link('編集', href: edit_activity_record_path(activity_record))
    end

    it '「削除」リンクが表示されること' do
      expect(page).to have_link('削除')
    end
  end

  # =========================================================
  # 編集フロー (edit → update)
  # =========================================================
  describe '編集フロー' do
    let!(:activity_record) do
      create(:activity_record, user: user, light_time: light_time, comment: '元のコメント', idle_duration: 0)
    end

    before { visit edit_activity_record_path(activity_record) }

    it '編集フォームが表示されること' do
      expect(page).to have_content('光の時間の活動記録編集')
      expect(page).to have_field('activity_record[comment]', with: '元のコメント')
    end

    context '正常な値に変更して「更新する」をクリックしたとき' do
      it '詳細ページへ遷移し、更新後の値が反映されること' do
        fill_in 'activity_record[comment]', with: '更新後のコメント'
        click_on '更新する'

        aggregate_failures do
          expect(page).to have_current_path(activity_record_path(activity_record))
          expect(page).to have_content(
            I18n.t('defaults.flash_message.updated', item: ActivityRecord.model_name.human)
          )
          expect(page).to have_content('更新後のコメント')
        end
      end
    end

    context '不正な値を入力して「更新する」をクリックしたとき' do
      it 'エラーメッセージとフラッシュメッセージが表示されること' do
        # HTML5 バリデーションを無効化してサーバーサイドバリデーションをテスト
        page.execute_script("document.querySelector('form').setAttribute('novalidate', true)")

        fill_in 'activity_record[idle_duration]', with: 9999
        click_on '更新する'

        aggregate_failures do
          expect(page).to have_content('は合計時間以下にしてください')
          expect(page).to have_content(
            I18n.t('defaults.flash_message.not_updated', item: ActivityRecord.model_name.human)
          )
          expect(page).to have_current_path(edit_activity_record_path(activity_record))
        end
      end
    end

    context '「キャンセル」をクリックしたとき' do
      it '詳細ページへ戻ること' do
        click_on 'キャンセル'
        expect(page).to have_current_path(activity_record_path(activity_record))
      end
    end
  end

  # =========================================================
  # 削除フロー (show → destroy)
  # =========================================================
  describe '削除フロー' do
    let!(:activity_record) do
      create(:activity_record, user: user, light_time: light_time, comment: '削除対象')
    end

    it '削除すると一覧から消えること' do
      visit activity_record_path(activity_record)
      accept_confirm { click_on '削除' }

      aggregate_failures do
        expect(page).to have_current_path(activity_records_path)
        expect(page).not_to have_content('削除対象')
        expect(page).to have_content(
          I18n.t('defaults.flash_message.deleted', item: ActivityRecord.model_name.human)
        )
      end
    end
  end
end
