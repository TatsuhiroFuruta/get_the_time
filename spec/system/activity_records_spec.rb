require "rails_helper"

RSpec.describe "ActivityRecords システムテスト", type: :system do
  let(:user) { create(:user) }
  # 固定文言「朝のランニング」「夜更かししてしまう」をそのまま使う
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before do
    sign_in user
  end

  describe "マイページからポモドーロタイマー画面への遷移" do
    it "「やること」を入力してスタートすると入力内容が引き継がれること" do
      visit mypage_path
      fill_in "やることを入力", with: "マイページからのタスク"
      click_on "スタート"

      aggregate_failures do
        expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)
        expect(page).to have_content("マイページからのタスク")
      end
    end

    it "スタート後にブラウザバック・フォワードで戻ってきても、未スタートの出口に揃うこと" do
      visit mypage_path
      click_on "スタート"
      expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)

      click_on "スタート", visible: true
      # 出口が入れ替わるのを待つ。startButton の hidden は押した直後に付くので、
      # fetch の往復が終わったことを表さない
      expect(page).to have_button("終了する", visible: true, wait: 5)

      # Turbo Drive は離脱時の（＝入れ替え済みの）DOM をキャッシュするので、
      # 復元では hidden が入れ替わったまま戻ってくる。connect() が未スタートの
      # 表示状態へ揃え直さないと、キャンセルの無い行き止まりが復活する。
      page.go_back
      expect(page).to have_current_path(mypage_path, ignore_query: true)
      page.go_forward
      expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)

      aggregate_failures do
        expect(page).to have_link("キャンセル", visible: true)
        expect(page).to have_no_button("終了する", visible: true)
        expect(page).to have_no_button("集中できない、やる気が出ないときは", visible: true)
      end
    end

    it "「やること」未入力でスタートしてもポモドーロタイマー画面に遷移できること" do
      visit mypage_path
      # やることを入力せずにスタート
      click_on "スタート"

      aggregate_failures do
        expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)
        # タイマー画面の主要要素が表示される
        expect(page).to have_content("25:00")
        expect(page).to have_content("朝のランニング")
        expect(page).to have_content("健康的な自分")
      end
    end
  end

  # =========================================================
  # ポモドーロタイマー画面
  # =========================================================
  describe "ポモドーロタイマー画面" do
    before { visit pomodoro_timer_activity_records_path }

    it "タイマー画面が表示されること" do
      aggregate_failures do
        expect(page).to have_content("25:00")
        expect(page).to have_content("朝のランニング")
        expect(page).to have_content("健康的な自分")
      end
    end

    it "スタート前はキャンセルだけが出口で、終了するとモチベーションボタンは表示されないこと" do
      aggregate_failures do
        expect(page).to have_button("スタート", visible: true)
        expect(page).to have_link("キャンセル", href: mypage_path, visible: true)
        # Capybara.ignore_hidden_elements = false なので visible: true の明示が要る
        expect(page).to have_no_button("終了する", visible: true)
        expect(page).to have_no_button("集中できない、やる気が出ないときは", visible: true)
      end
    end

    it "キャンセルをクリックするとマイページへ戻ること" do
      click_on "キャンセル", visible: true

      aggregate_failures do
        expect(page).to have_current_path(mypage_path, ignore_query: true)
        expect(user.activity_records.count).to eq(0)
      end
    end

    context "スタートボタンをクリックした後" do
      before do
        click_on "スタート", visible: true
        # 出口の入れ替えが済むのを待つ
        expect(page).to have_button("集中できない、やる気が出ないときは", visible: true)
      end

      it "キャンセルが消えて終了するとモチベーションボタンが表示されること" do
        aggregate_failures do
          expect(page).to have_button("終了する", visible: true)
          expect(page).to have_no_link("キャンセル", visible: true)
        end
      end

      it "「集中できない、やる気が出ないときは」をクリックするとモチベーション画面が表示されること" do
        click_on "集中できない、やる気が出ないときは", visible: true
        aggregate_failures do
          expect(page).to have_selector('[data-pomodoro-target="motivationScreen"]:not(.hidden)')
          expect(page).to have_selector('[data-pomodoro-target="workScreen"].hidden')
          expect(page).to have_content("夜更かししてしまう")
          expect(page).to have_content("健康を損なう")
        end
      end

      it "モチベーション画面で「いいえ、もう少し頑張ります！」をクリックすると作業画面に戻ること" do
        click_on "集中できない、やる気が出ないときは", visible: true
        click_on "いいえ、もう少し頑張ります！"
        aggregate_failures do
          expect(page).to have_selector('[data-pomodoro-target="workScreen"]:not(.hidden)')
          expect(page).to have_selector('[data-pomodoro-target="motivationScreen"].hidden')
          expect(page).to have_content("朝のランニング")
        end
      end
    end

    context "やること入力フォームに入力して「更新する」をクリックしたとき" do
      it "やること表示エリアが入力内容に更新されること" do
        fill_in "やることを入力", with: "今日のタスク"
        click_on "更新する"
        expect(page).to have_content("今日のタスク")
      end
    end
  end

  # =========================================================
  # ポモドーロタイマー動作中
  # =========================================================
  describe "ポモドーロタイマー動作中" do
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

    context "スタートボタンをクリックしたとき" do
      it "スタートボタンが非表示になりタイマーが動き始めること" do
        click_on "スタート", visible: true
        aggregate_failures do
          expect(page).not_to have_button("スタート", visible: true)
          expect(page).to have_content("00:02", wait: 3)
        end
      end

      it "浄化タイマーの問い合わせ中に二度押ししても作業タイマーが二重に走らないこと" do
        page.execute_script(<<~JS)
          const el = document.querySelector('[data-controller="pomodoro"]')
          const controller = window.Stimulus.getControllerForElementAndIdentifier(el, 'pomodoro')

          // 作業を60秒に戻す。3秒のままだとテスト中に満了して、休憩用の
          // setInterval が 2 本目として数えられてしまう
          el.dataset.pomodoroWorkDurationValue = 60

          // fetch の往復を 1 秒に引き伸ばして、二度押しが入る窓を作る
          controller.isPurificationCounting = () => new Promise(r => setTimeout(() => r(false), 1000))

          // 作られた setInterval の間隔を記録する（startTimer は 1000ms）
          window.__intervalMs = []
          const orig = window.setInterval
          window.setInterval = function (fn, ms, ...rest) {
            window.__intervalMs.push(ms)
            return orig.call(window, fn, ms, ...rest)
          }

          controller.startButtonTarget.click()
          setTimeout(() => controller.startButtonTarget.click(), 200)
        JS

        # 遅延が明けてタイマーが動き出したことを、残り時間が減ることで確認する
        expect(page).to have_content("00:59", wait: 10)

        # startTimer() 由来（1 秒間隔）の interval が 1 本だけであること。
        # 2 本作られると片方が this.timerInterval の上書きで参照を失い、
        # 二度と clearInterval できなくなる（#265）
        expect(page.evaluate_script("window.__intervalMs.filter(ms => ms === 1000).length")).to eq(1)
      end
    end

    context "作業時間が終了したとき" do
      it "休憩画面に切り替わりポモドーロ数が1になること" do
        click_on "スタート", visible: true

        aggregate_failures do
          # 1. 休憩画面（breakScreenターゲット）が目に見える状態になっていること
          expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)

          # 2. 作業画面（workScreenターゲット）が非表示になっていること
          expect(page).to have_selector('[data-pomodoro-target="workScreen"].hidden')

          # 3. ポモドーロ数のカウントアップを確認
          expect(page).to have_content("ポモドーロ数：1", wait: 10)

          # 4. 休憩画面の中身を網羅的に検証
          within('[data-pomodoro-target="breakScreen"]') do
            expect(page).to have_css('img[src*="timer"]') # timer.png があるか
            expect(page).to have_button("集中できない、やる気が出ないときは", visible: true)
            expect(page).to have_button("終了する", visible: true)
          end
        end
      end
    end

    context "休憩時間が終了したとき" do
      it "作業画面に戻りスタートボタンが表示されること" do
        click_on "スタート", visible: true
        # スタートが完了した（＝出口が入れ替わった）ことを待つ。ここを飛ばすと
        # まだ見えている元のスタートボタンにマッチし、休憩サイクルを回さずに通る
        expect(page).to have_button("終了する", visible: true, wait: 5)

        aggregate_failures do
          # 作業3秒 + 休憩2秒 終了後にスタートボタンが再表示される
          expect(page).to have_button("スタート", visible: true, wait: 15)
          expect(page).to have_content("ポモドーロ数：1", wait: 15)
        end
      end

      it "休憩明けの作業画面では「スタート」「終了する」「集中できない…」が並び、「キャンセル」は戻らないこと" do
        click_on "スタート", visible: true
        # 同上。ここを飛ばすと休憩明けを経ずに assertion が満たされてしまう
        expect(page).to have_button("終了する", visible: true, wait: 5)
        expect(page).to have_button("スタート", visible: true, wait: 15)

        # 初回スタートで入れ替えた出口は、休憩明けの作業画面でも元に戻さない
        within('[data-pomodoro-target="workScreen"]') do
          aggregate_failures do
            expect(page).to have_button("終了する", visible: true)
            expect(page).to have_button("集中できない、やる気が出ないときは", visible: true)
            expect(page).to have_no_link("キャンセル", visible: true)
          end
        end
      end
    end

    # =========================================================
    # 無操作タイムアウト（2回目以降のセッション）
    # =========================================================
    context "2回目以降のセッションで無操作タイムアウトが発生したとき" do
      before do
        # 無操作タイムアウトも短縮（2秒）、チェック間隔も短縮（0.5秒）
        page.execute_script(<<~JS)
          const el = document.querySelector('[data-controller="pomodoro"]')
          const controller = window.Stimulus.getControllerForElementAndIdentifier(el, 'pomodoro')
          controller.inactivityTimeout = 2000  // タイムアウト2秒
          controller.checkInterval = 500       // 0.5秒ごとにチェック
        JS

        # 1回目のポモドーロを完了させて休憩画面へ
        click_on "スタート", visible: true

        # 作業時間（3秒）終了を待つ → 休憩画面へ切り替わる
        expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)
        # 休憩時間（2秒）終了を待つ → 作業画面に戻りスタートボタンが表示される
        # visible: true が無いと、ignore_hidden_elements = false のせいで hidden の
        # ままのボタンに即マッチし、休憩明けを待たずに次へ進んでしまう
        expect(page).to have_button("スタート", visible: true, wait: 10)
        # この時点で inactivityCheck が開始されている
      end

      it "無操作タイムアウト後に自動で新規作成画面へ遷移すること" do
        accept_alert(wait: 10)
        expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
      end
      # ✕ テストせず目視で確認する：タイムアウト時間の正確性（20分かどうか）
      # 手動の動作確認で担保
    end

    # =========================================================
    # 終了ボタン後に新規作成画面へ遷移
    # =========================================================
    describe "終了ボタンをクリックしたとき" do
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

      # 作業画面の「終了する」を押す系のテストでは、作業3秒のままだと
      # 「スタート → startButton の hidden 待ち → 終了するのクリック」が
      # 3秒を超えた瞬間に作業画面が隠れ、クリック対象を見失う（CI 高負荷時）。
      # 尺を伸ばしてこのレースを外す。
      def relax_timer_durations
        page.execute_script(<<~JS)
          const el = document.querySelector('[data-controller="pomodoro"]')
          el.dataset.pomodoroWorkDurationValue = 60
          el.dataset.pomodoroBreakDurationValue = 30
        JS
      end

      # 作業タイマーの締切を直近に動かす。setInterval が生きていれば 1 秒以内に
      # onTimerComplete が走って休憩画面へ切り替わり、死んでいれば何も起きない。
      # 「実時間が経ったか」ではなく「タイマーが生きているか」だけを見るための細工。
      def expire_work_timer_soon
        page.execute_script(<<~JS)
          const el = document.querySelector('[data-controller="pomodoro"]')
          const controller = window.Stimulus.getControllerForElementAndIdentifier(el, 'pomodoro')
          controller.endedAt = new Date(Date.now() + 500)
        JS
      end

      context "作業画面から終了したとき" do
        it "スタート後に終了すると確認ダイアログを経て新規作成画面へ遷移すること" do
          relax_timer_durations
          click_on "スタート", visible: true
          # スタートが完了してタイマーが動き出すのを待つ
          expect(page).to have_button("終了する", visible: true, wait: 5)

          accept_confirm("終了してよろしいでしょうか？") do
            within('[data-pomodoro-target="workScreen"]') do
              click_on "終了する", visible: true
            end
          end

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end

        it "確認ダイアログをキャンセルするとタイマーが継続すること" do
          relax_timer_durations
          click_on "スタート", visible: true
          expect(page).to have_button("終了する", visible: true, wait: 5)

          dismiss_confirm("終了してよろしいでしょうか？") do
            within('[data-pomodoro-target="workScreen"]') do
              click_on "終了する", visible: true
            end
          end

          # 確認を clearInterval より前に通していれば、キャンセル後もタイマーは生きている
          expire_work_timer_soon

          aggregate_failures do
            # 遷移していないこと
            expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)
            # タイマーが生きていれば締切の到来で休憩画面へ切り替わる。
            # clearInterval されていればここで止まったままになる。
            expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)
            expect(page).to have_content("ポモドーロ数：1", wait: 10)
          end
        end
      end

      context "休憩画面から終了したとき" do
        before do
          # 休憩2秒のままだと、休憩画面の検出 → 終了するのクリックが2秒を超えた瞬間に
          # switchToWorkMode() が走り、breakScreen が hidden のまま二度と戻らない。
          # 作業は3秒のままにして休憩画面へ速く入り、休憩尺だけ伸ばす。
          page.execute_script(<<~JS)
            document.querySelector('[data-controller="pomodoro"]').dataset.pomodoroBreakDurationValue = 30
          JS

          click_on "スタート", visible: true
          # 作業時間終了を待つ → 休憩画面へ
          expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)
        end

        it "新規作成画面へ遷移すること" do
          accept_confirm("終了してよろしいでしょうか？") do
            within('[data-pomodoro-target="breakScreen"]') do
              click_on "終了する", visible: true
            end
          end

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end
      end

      context "モチベーション画面の「それでいいもん」をクリックしたとき" do
        before do
          # 作業3秒のままだと、モチベーションボタンのクリックが3秒を超えた瞬間に
          # 休憩画面へ切り替わり、workScreen が hidden になってクリック対象を見失う
          relax_timer_durations

          click_on "スタート", visible: true
          within('[data-pomodoro-target="workScreen"]') do
            click_on "集中できない、やる気が出ないときは", visible: true
          end
          expect(page).to have_selector('[data-pomodoro-target="motivationScreen"]:not(.hidden)', wait: 5)
        end

        it "新規作成画面へ遷移すること" do
          click_on "それでいいもん"

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end
      end
    end
  end

  # =========================================================
  # 登録フロー (new → create)
  # =========================================================
  describe "登録フロー" do
    let(:form_params) do
      {
        activity_record_form: {
          started_at:     1.hour.ago.iso8601,
          ended_at:       Time.current.iso8601,
          total_duration: 60,
          task:           "システムテストタスク",
          light_time_id:  light_time.id
        }
      }
    end

    before { visit new_activity_record_path(form_params) }

    it "登録フォームが表示されること" do
      aggregate_failures do
        expect(page).to have_content("光の時間の活動記録登録")
        expect(page).to have_content("朝のランニング")
        expect(page).to have_content("60")
      end
    end

    context "評価項目をすべて選択して「記録する」をクリックしたとき" do
      it "一覧ページへ遷移し、フラッシュメッセージが表示されること" do
        # rating_field ヘルパーが生成するラジオボタンを選択（value="3"）
        %w[satisfaction progress quality focus fatigue].each do |attr|
          find("input[name='activity_record_form[#{attr}]'][value='3']").choose
        end

        click_on "記録する"

        aggregate_failures do
          expect(page).to have_current_path(activity_records_path)
          expect(page).to have_content(
            I18n.t("defaults.flash_message.created", item: ActivityRecordForm.model_name.human)
          )
        end
      end

      it "浄化タイマー獲得モーダルが表示され、OKをクリックすると閉じること" do
        allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10)

        %w[satisfaction progress quality focus fatigue].each do |attr|
          find("input[name='activity_record_form[#{attr}]'][value='3']").choose
        end

        click_on "記録する"

        # モーダルが表示されている
        # total_duration: 60 → 2ブロック × 10分（スタブ固定）= 20分付与
        expect(page).to have_content("浄化タイマーを20分獲得！")

        # OKボタンをクリックするとモーダルが閉じる
        click_on "OK"

        # closeアクションで display:none になるまで待つ（setTimeoutで300ms）
        expect(page).to have_selector('[data-controller="grant-purification-time-modal"]', visible: :hidden, wait: 5)
      end
    end

    context "total_duration が 30分未満で記録したとき" do
      let(:form_params) do
        {
          activity_record_form: {
            started_at:     1.hour.ago.iso8601,
            ended_at:       Time.current.iso8601,
            total_duration: 20,  # ← 30分未満
            task:           "システムテストタスク",
            light_time_id:  light_time.id
          }
        }
      end

      it "浄化タイマー獲得モーダルが表示されないこと" do
        %w[satisfaction progress quality focus fatigue].each do |attr|
          find("input[name='activity_record_form[#{attr}]'][value='3']").choose
        end

        click_on "記録する"

        aggregate_failures do
          expect(page).to have_current_path(activity_records_path)
          # モーダルのテキストが表示されないこと
          expect(page).not_to have_content("浄化タイマーを")
          expect(page).not_to have_content("獲得！")
        end
      end
    end

    context "評価項目を未選択のまま「記録する」をクリックしたとき" do
      it "エラーメッセージとフラッシュメッセージが表示されること" do
        click_on "記録する"

        aggregate_failures do
          # 各評価項目のエラーメッセージ
          %w[satisfaction progress quality focus fatigue].each do |attr|
            expect(page).to have_content("について、1から5のいずれかを選択してください")
          end

          # フラッシュメッセージ
          expect(page).to have_content(
            I18n.t("defaults.flash_message.not_created", item: ActivityRecordForm.model_name.human)
          )

          # 登録フォームに留まっていること
          expect(page).to have_current_path(new_activity_record_path, ignore_query: true)
        end
      end
    end

    it "「記録しない」をクリックするとマイページへ遷移すること" do
      click_on "記録しない"
      expect(page).to have_current_path(mypage_path)
    end
  end

  # =========================================================
  # 一覧画面 (index)
  # =========================================================
  describe "一覧画面" do
    context "活動記録がないとき" do
      it "未登録メッセージが表示されること" do
        visit activity_records_path
        expect(page).to have_content("光の時間の活動記録が登録されていません")
      end
    end

    context "活動記録があるとき" do
      let!(:activity_record) do
        create(:activity_record, user: user, light_time: light_time, comment: "集中できた日")
      end

      it "光の時間の活動内容とコメントが一覧に表示されること" do
        visit activity_records_path
        aggregate_failures do
          expect(page).to have_content("朝のランニング")
          expect(page).to have_content("集中できた日")
        end
      end

      it "レコードをクリックすると詳細ページへ遷移すること" do
        visit activity_records_path
        find("a", text: "朝のランニング").click
        expect(page).to have_current_path(activity_record_path(activity_record))
      end
    end

    context "お気に入りトグル" do
      let!(:activity_record) do
        create(:activity_record, user: user, light_time: light_time, comment: "お気に入り対象")
      end

      it "☆ をクリックすると ★ に切り替わり、レコードが favorited になること" do
        visit activity_records_path

        within("##{ActionView::RecordIdentifier.dom_id(activity_record)}") do
          expect(page).to have_button("お気に入りに追加")
          click_on "お気に入りに追加"
          expect(page).to have_button("お気に入りを解除")
        end

        expect(activity_record.reload.favorited).to be true
      end

      it "★ をクリックすると ☆ に戻り、favorited が false になること" do
        activity_record.update!(favorited: true)
        visit activity_records_path

        within("##{ActionView::RecordIdentifier.dom_id(activity_record)}") do
          expect(page).to have_button("お気に入りを解除")
          click_on "お気に入りを解除"
          expect(page).to have_button("お気に入りに追加")
        end

        expect(activity_record.reload.favorited).to be false
      end
    end

    context "検索フォームを使ったとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, comment: "検索ヒット")
        create(:activity_record, user: user, light_time: light_time, comment: "対象外")
      end

      it "検索ワードに一致するレコードだけ表示されること" do
        visit activity_records_path
        fill_in "コメント or 活動内容で検索", with: "検索ヒット"
        click_on "検索"
        aggregate_failures do
          expect(page).to have_content("検索ヒット")
          expect(page).not_to have_content("対象外")
        end
      end

      it "一致しないワードのとき「検索結果が見つかりませんでした」と表示されること" do
        visit activity_records_path
        fill_in "コメント or 活動内容で検索", with: "存在しないキーワード"
        click_on "検索"
        expect(page).to have_content("検索結果が見つかりませんでした")
      end
    end

    context "お気に入りで絞り込みするとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, comment: "お気に入り対象", favorited: true)
        create(:activity_record, user: user, light_time: light_time, comment: "通常レコード", favorited: false)
      end

      it "「★ お気に入り」タブをクリックするとお気に入りのみ表示されること" do
        visit activity_records_path
        click_on "★ お気に入り"

        aggregate_failures do
          expect(page).to have_content("お気に入り対象")
          expect(page).not_to have_content("通常レコード")
        end
      end

      it "「すべて」タブをクリックすると全件表示されること" do
        visit activity_records_path(q: { favorited_eq: true })

        # まずお気に入りのみ表示されていることを確認
        aggregate_failures do
          expect(page).to have_content("お気に入り対象")
          expect(page).not_to have_content("通常レコード")
        end

        click_on "すべて"

        aggregate_failures do
          expect(page).to have_content("お気に入り対象")
          expect(page).to have_content("通常レコード")
        end
      end
    end

    context "お気に入りタブでお気に入りが1件もないとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, favorited: false)
      end

      it "お気に入り未登録のメッセージが表示されること" do
        visit activity_records_path
        click_on "★ お気に入り"
        expect(page).to have_content("お気に入りの活動記録がありません。★をクリックして追加できます")
      end
    end
  end

  # =========================================================
  # 一覧画面（カードデザイン）
  # =========================================================
  describe "一覧画面（カードデザイン）" do
    it "今日の本来の自分・計測時間・やることが表示されること" do
      create(:activity_record, user: user, light_time: light_time,
             total_duration: 60, idle_duration: 0, task: "学習する", comment: "集中できた")
      visit activity_records_path

      aggregate_failures do
        expect(page).to have_content("今日の本来の自分")
        expect(page).to have_content("100.0 %")  # (60 - 0) / 60 = 100%
        expect(page).to have_content("60 分")
        expect(page).to have_content("光の時間での行動：")
        expect(page).to have_content("やること：")
        expect(page).to have_content("コメント：")
        expect(page).to have_content("学習する")
      end
    end

    it "10文字を超える内容は先頭10文字+「...」で省略表示されること" do
      record = create(:activity_record, user: user, light_time: light_time,
                      task: "今日もよく頑張ったよヨヨヨ")  # 13文字
      visit activity_records_path

      within("##{ActionView::RecordIdentifier.dom_id(record)}") do
        aggregate_failures do
          expect(page).to have_content("今日もよく頑張ったよ...")
          expect(page).not_to have_content("今日もよく頑張ったよヨヨヨ")
        end
      end
    end

    it "やること・コメントが未記入のときは「...」が表示されること" do
      record = create(:activity_record, user: user, light_time: light_time,
                      task: "", comment: "")
      visit activity_records_path

      within("##{ActionView::RecordIdentifier.dom_id(record)}") do
        expect(page).to have_content("...")
      end
    end
  end

  # =========================================================
  # 一覧画面（ページネーション）
  # =========================================================
  describe "一覧画面（ページネーション）" do
    context "活動記録が10件以上あるとき" do
      before do
        # 10件作成（per_page: 9 を超える件数）
        10.times do |i|
          create(:activity_record, user: user, light_time: light_time, comment: "コメント#{i + 1}")
        end
        visit activity_records_path
      end

      it "1ページ目には9件まで表示されること" do
        # 10件のうち9件のみ表示
        within('[data-test="activity-records-list"]') do
          expect(page).to have_selector(".bg-amber-500", count: 9)
        end
      end

      it "ページネーションリンクが表示されること" do
        expect(page).to have_selector('[data-test="pagination"]')
      end

      it "2ページ目をクリックすると残りのレコードが表示されること" do
        click_on "2"

        aggregate_failures do
          expect(page).to have_current_path(activity_records_path, ignore_query: true)
          # 10件目（=最も古いレコード）が表示される
          # created_at: desc 順なので、最初に作ったレコード = 「コメント1」が2ページ目に来る
          expect(page).to have_content("コメント1")
        end
      end
    end

    context "活動記録が9件以下のとき" do
      before do
        9.times { create(:activity_record, user: user, light_time: light_time) }
        visit activity_records_path
      end

      it "ページネーションリンクが表示されないこと" do
        expect(page).not_to have_selector('[data-test="pagination"]')
      end
    end
  end

  # =========================================================
  # 詳細画面 (show)
  # =========================================================
  describe "詳細画面" do
    let!(:activity_record) do
      create(:activity_record, :high_rating,
             user: user, light_time: light_time,
             task: "詳細確認タスク", comment: "詳細コメント",
             total_duration: 60, idle_duration: 5)
    end

    before { visit activity_record_path(activity_record) }

    it "各項目が表示されること" do
      aggregate_failures do
        expect(page).to have_content("朝のランニング")
        expect(page).to have_content("詳細確認タスク")
        expect(page).to have_content("詳細コメント")
        expect(page).to have_content("60")
        expect(page).to have_content("5")
      end
    end

    it "「編集」リンクが表示されること" do
      expect(page).to have_link("編集", href: edit_activity_record_path(activity_record))
    end

    it "「削除」リンクが表示されること" do
      expect(page).to have_link("削除")
    end

    it "コメントの改行が保持されて表示されること" do
      activity_record.update!(comment: "コメント1\nコメント2")

      visit activity_record_path(activity_record)

      expect(page).to have_css("div.whitespace-pre-wrap", text: "コメント1")
    end
  end

  # =========================================================
  # 編集フロー (edit → update)
  # =========================================================
  describe "編集フロー" do
    let!(:activity_record) do
      create(:activity_record, user: user, light_time: light_time, comment: "元のコメント", idle_duration: 0)
    end

    before { visit edit_activity_record_path(activity_record) }

    it "編集フォームが表示されること" do
      aggregate_failures do
        expect(page).to have_content("光の時間の活動記録編集")
        expect(page).to have_field("activity_record[comment]", with: "元のコメント")
      end
    end

    context "正常な値に変更して「更新する」をクリックしたとき" do
      it "詳細ページへ遷移し、更新後の値が反映されること" do
        fill_in "activity_record[comment]", with: "更新後のコメント"
        click_on "更新する"

        aggregate_failures do
          expect(page).to have_current_path(activity_record_path(activity_record))
          expect(page).to have_content(
            I18n.t("defaults.flash_message.updated", item: ActivityRecord.model_name.human)
          )
          expect(page).to have_content("更新後のコメント")
        end
      end
    end

    context "不正な値を入力して「更新する」をクリックしたとき" do
      it "エラーメッセージとフラッシュメッセージが表示されること" do
        # HTML5 バリデーションを無効化してサーバーサイドバリデーションをテスト
        page.execute_script("document.querySelector('form').setAttribute('novalidate', true)")

        fill_in "activity_record[idle_duration]", with: 9999
        click_on "更新する"

        aggregate_failures do
          expect(page).to have_content("は合計時間以下にしてください")
          expect(page).to have_content(
            I18n.t("defaults.flash_message.not_updated", item: ActivityRecord.model_name.human)
          )
          expect(page).to have_current_path(edit_activity_record_path(activity_record))
        end
      end
    end

    context "「キャンセル」をクリックしたとき" do
      it "詳細ページへ戻ること" do
        click_on "キャンセル"
        expect(page).to have_current_path(activity_record_path(activity_record))
      end
    end
  end

  # =========================================================
  # 削除フロー (show → destroy)
  # =========================================================
  describe "削除フロー" do
    let!(:activity_record) do
      create(:activity_record, user: user, light_time: light_time, comment: "削除対象")
    end

    it "削除すると一覧から消えること" do
      visit activity_record_path(activity_record)
      accept_confirm { click_on "削除" }

      aggregate_failures do
        expect(page).to have_current_path(activity_records_path)
        expect(page).not_to have_content("削除対象")
        expect(page).to have_content(
          I18n.t("defaults.flash_message.deleted", item: ActivityRecord.model_name.human)
        )
      end
    end
  end
end
