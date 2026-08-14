require "rails_helper"

RSpec.describe "タイマーの排他制御", type: :system do
  let(:user) { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time) { create(:dark_time, user: user) }
  let!(:pomodoro_setting) { user.pomodoro_setting }

  before { sign_in user }

  # =========================================================
  # ガード A: 浄化タイマー計測中 → ポモドーロ画面に入れない（サーバ側）
  # =========================================================
  describe "浄化タイマーの計測中" do
    let!(:purification_time) { create(:purification_time, :running, user: user) }

    it "ポモドーロ画面を開こうとするとマイページへ追い返されること" do
      visit pomodoro_timer_activity_records_path

      aggregate_failures do
        expect(page).to have_current_path(mypage_path)
        expect(page).to have_content("浄化タイマーの実行中はポモドーロタイマーを開始できません")
      end
    end
  end

  # =========================================================
  # ガード B: 光の時間の活動中 → 浄化タイマー画面に入れない（クライアント側リース）
  # =========================================================
  describe "ポモドーロの計測中" do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    it "別タブで浄化タイマー画面を開こうとするとマイページへ追い返されること" do
      visit pomodoro_timer_activity_records_path
      click_button "スタート"

      # リースが書き込まれるのを待つ。startButton の hidden は「押した」だけを表し、
      # リース取得は fetch の往復後なので同期ポイントにならない。
      # 「終了する」の表示は startActivityLock() の直後なので、これを待つ。
      expect(page).to have_button("終了する", visible: true)

      new_window = open_new_window
      within_window new_window do
        visit purification_time_path

        aggregate_failures do
          expect(page).to have_current_path(mypage_path, ignore_query: true)
          expect(page).to have_content("別のタブで光の時間の活動を実行中です")
        end
      end
    end

    it "別タブでポモドーロ画面を開こうとしてもマイページへ追い返されること（光の時間の活動は 1 つだけ）" do
      visit pomodoro_timer_activity_records_path
      click_button "スタート"
      # リースが書き込まれるのを待つ（同期ポイントの理由は上記コメント参照）
      expect(page).to have_button("終了する", visible: true)

      new_window = open_new_window
      within_window new_window do
        visit pomodoro_timer_activity_records_path
        expect(page).to have_current_path(mypage_path, ignore_query: true)
      end
    end
  end

  describe "ポモドーロを開始していないとき" do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    it "タイマー画面を開いているだけでは浄化タイマーをブロックしないこと" do
      visit pomodoro_timer_activity_records_path

      new_window = open_new_window
      within_window new_window do
        visit purification_time_path
        expect(page).to have_current_path(purification_time_path)
      end
    end
  end

  # =========================================================
  # 両タブを開いた「後」でどちらかをスタートしたときの後出しジャンケン
  # （connect 時のガードだけでは検知できない、スタート押下時点のガードの検証）
  # =========================================================
  describe "両タブを先に開いてから、後出しでどちらかをスタートしたとき" do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    # このケースを実際に止めているのは storage イベントによる追い返しである。
    # 別タブがリースを書いた瞬間に浄化タイマー画面がマイページへ退避するため、
    # スタートボタンを押す機会そのものが無くなる。
    # purification_timer_controller#start にも heldByOther? の確認を入れてあるが、
    # それは storage イベントを取り逃した場合の最後の砦であり、ブラウザ上では
    # 再現できないため、この spec では検証していない（多層防御として残している）。
    it "浄化タイマー画面を開いたまま、別タブでポモドーロを開始すると、浄化タイマー画面が追い返されて開始できないこと" do
      # 浄化タイマー画面を先に開く（この時点ではまだどちらのロックも無いのでガードは通る）
      visit purification_time_path

      new_window = open_new_window
      within_window new_window do
        visit pomodoro_timer_activity_records_path
        click_button "スタート"
        # リースが書き込まれるのを待つ（同期ポイントの理由は上記コメント参照）
        expect(page).to have_button("終了する", visible: true)
      end

      aggregate_failures do
        expect(page).to have_current_path(mypage_path, ignore_query: true)
        expect(page).to have_content("別のタブで光の時間の活動を実行中です")
        expect(user.purification_time.reload).not_to be_running
      end
    end

    it "ポモドーロ画面を開いたまま、別タブで浄化タイマーを開始したとき、ポモドーロのスタートを押しても開始できないこと" do
      # ポモドーロ画面を先に開く（この時点では浄化タイマーは計測中ではないのでガードは通る）
      visit pomodoro_timer_activity_records_path

      new_window = open_new_window
      within_window new_window do
        visit purification_time_path
        click_button "スタート"
        # サーバ側で running になるまで待つ（reload 後に「終了する」ボタンが出る）
        expect(page).to have_button("終了する", wait: 5)
      end

      click_button "スタート", visible: true

      aggregate_failures do
        expect(page).to have_current_path(mypage_path, ignore_query: true)
        expect(page).to have_content("浄化タイマーの実行中はポモドーロタイマーを開始できません")
        expect(user.activity_records.count).to eq(0)
      end
    end
  end

  # =========================================================
  # スタート押下から fetch が返るまでの間に離脱したとき
  # =========================================================
  describe "浄化タイマーへの問い合わせ中にキャンセルで離脱したとき" do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    # 「キャンセル」は Turbo Drive のリンク遷移なので document は作り直されず、
    # disconnect() が済んだ後もスタート処理の Promise だけが再開する。そこで
    # リースを張ってしまうと、片付ける者がいないまま heartbeat が回り続け、
    # ユーザーは浄化タイマーへ二度と入れなくなる。
    it "往復が明けてもリースが張られないこと" do
      visit pomodoro_timer_activity_records_path

      # 問い合わせを、テストから明示的に解決できる Promise に差し替える
      page.execute_script(<<~JS)
        const el = document.querySelector('[data-controller="pomodoro"]')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, 'pomodoro')
        controller.isPurificationCounting = () => new Promise(r => { window.__resolvePurification = () => r(false) })
        controller.startButtonTarget.click()
      JS

      # 往復が終わる前に離脱する（この時点ではまだ「キャンセル」が出ている）
      click_on "キャンセル", visible: true
      expect(page).to have_current_path(mypage_path, ignore_query: true)

      # 遷移後に往復が明ける。window は Turbo 遷移でも作り直されないので Promise は生きている
      page.execute_script("window.__resolvePurification()")

      aggregate_failures do
        expect(page.evaluate_script("localStorage.getItem('gtt:activity_lock')")).to be_nil

        # 別タブから浄化タイマーへ入れること（リースが無いことの利用者から見た確認）
        new_window = open_new_window
        within_window new_window do
          visit purification_time_path
          expect(page).to have_current_path(purification_time_path)
        end
      end
    end
  end

  # =========================================================
  # Turbo Drive 下での離脱（pagehide が発火しないケース）
  # =========================================================
  describe "活動記録フォームから Turbo 遷移で離脱したとき" do
    let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

    it "「記録しない」で離脱すると、猶予（5秒）経過後には別タブから浄化タイマーへ入れること" do
      visit pomodoro_timer_activity_records_path
      click_button "スタート", visible: true
      # リースが書き込まれるのを待つ（startButton の hidden では早すぎる）
      expect(page).to have_button("終了する", visible: true)

      accept_confirm("終了してよろしいでしょうか？") do
        within('[data-pomodoro-target="workScreen"]') do
          click_on "終了する", visible: true
        end
      end
      expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)

      # 「記録しない」は Turbo Drive の通常リンク遷移であり document を作り直さない
      # ため pagehide は発火しない。disconnect() での orphan() 呼び出しが無いと
      # リースは満了（3分）まで生き続けてしまう。
      click_on "記録しない"
      expect(page).to have_current_path(mypage_path, ignore_query: true)

      new_window = open_new_window
      within_window new_window do
        # orphan() によって猶予は 5 秒に短縮される。JS 側の実時刻は travel_to で
        # 動かせないため、実際に猶予が切れるまで visit をリトライして待つ
        # （bare sleep で決め打ちの時間を待つのではなく、実際の失効を都度確認する）。
        deadline = Time.now + Capybara.default_max_wait_time
        loop do
          visit purification_time_path
          break if page.current_path == purification_time_path || Time.now > deadline
        end

        expect(page).to have_current_path(purification_time_path)
      end
    end
  end
end
