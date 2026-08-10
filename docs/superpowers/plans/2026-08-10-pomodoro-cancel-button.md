# ポモドーロタイマー画面のキャンセルボタンと終了確認 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ポモドーロタイマー画面で、未スタート時の出口を「終了する」から「キャンセル（マイページへ）」に変え、計測中の「終了する」には確認ダイアログを挟む。

**Architecture:** サーバ側の変更はゼロ。Stimulus コントローラ（`pomodoro_controller.js`）が持つ「初回スタート済みか」という既存の状態（`firstStartedAt`）に、ボタンの表示切り替えを 1 回だけ紐づける。確認ダイアログはネイティブ `window.confirm()` を使い、`finish()`（確認あり）と `giveUp()`（確認なし）の 2 入口から共通の `completeSession()` を呼ぶ形に分割する。

**Tech Stack:** Rails 8.1 / Hotwire (Stimulus) / esbuild / Tailwind CSS v4 / RSpec + Capybara + Selenium

**関連:** issue [#263](https://github.com/TatsuhiroFuruta/get_the_time/issues/263) / 設計書 `docs/superpowers/specs/2026-08-10-pomodoro-cancel-button-design.md` / ブランチ `feature/pomodoro-cancel-button-263`

## Global Constraints

- UI 文言・コメント・フラッシュメッセージはすべて**日本語**（デフォルトロケール `:ja`）。
- 文字列は**ダブルクォート**。`spec/**/*` も対象（`.rubocop.yml`）。
- テストは **RSpec**（Minitest ではない）。`bin/rails test` は使わない。
- コマンドは Docker 前提。`docker compose exec web` を前置する（ローカルに直接 Ruby/Node がある場合は外す）。
- **`Capybara.ignore_hidden_elements = false`**（`spec/support/capybara.rb:47`）。`have_button("終了する")` は**非表示の要素にもマッチする**。表示・非表示を検証するときは必ず `visible: true` / `visible: :all` を明示するか、`.hidden` クラスを CSS セレクタで直接見ること。
- JS を変更したら、`docker compose exec web` で個別に rspec を回す前に `docker compose exec web yarn build` を実行する（`docker compose up` で起動中なら esbuild watcher が自動でリビルドするので不要）。
- `PurificationTimeGranter` / `ActivityRecordForm` などサーバ側の書き込み経路には**一切触れない**。本計画はビューと Stimulus コントローラのみを変更する。

## File Structure

| ファイル | 役割 | 変更内容 |
|---|---|---|
| `app/views/activity_records/pomodoro/_timer_buttons.html.erb` | 作業画面のボタン群 | 「キャンセル」を追加、「終了する」を初期非表示に |
| `app/views/activity_records/pomodoro/_motivation_screen.html.erb` | モチベーション画面 | 「それでいいもん」の action を `giveUp` に |
| `app/javascript/controllers/pomodoro_controller.js` | タイマーの全状態管理 | targets 追加、`start()` で出口を入れ替え、`finish()` を 3 メソッドに分割 |
| `app/views/static_pages/how_to_use/_step3.html.erb` | 使い方ページ | 「ブラウザの戻るボタンで戻りましょう」をキャンセルボタン案内に |
| `spec/system/activity_records_spec.rb` | ポモドーロ画面のシステムテスト | 既存 4 件を修正、2 件を新規追加 |
| `spec/system/timer_exclusion_spec.rb` | 排他制御のシステムテスト | 作業画面「終了する」のクリックに `accept_confirm` |

`_break_screen.html.erb` は**変更しない**。休憩画面の「終了する」は休憩に入る時点で必ずスタート済みなので表示制御が不要で、確認ダイアログは `finish()` 側に入るため自動的に効く。

---

### Task 1: 未スタート時の出口を「キャンセル」にする

**Files:**
- Modify: `app/views/activity_records/pomodoro/_timer_buttons.html.erb`（全体を置き換え）
- Modify: `app/javascript/controllers/pomodoro_controller.js:6`（targets）, `:84-98`（`start()` の初回ブロック）
- Modify: `app/views/static_pages/how_to_use/_step3.html.erb:37-39`
- Test: `spec/system/activity_records_spec.rb:54-65`

**Interfaces:**
- Consumes: 既存の `this.firstStartedAt`（初回スタート時刻。`null` なら未スタート）、既存の i18n キー `shared.buttons.cancel`（= 「キャンセル」、`config/locales/views/ja.yml:4`）、既存の `mypage_path`
- Produces: DOM ターゲット `data-pomodoro-target="cancelButton"` / `data-pomodoro-target="finishButton"`。`finishButton` は初期状態で `hidden` クラスを持ち、初回スタート後に外れる。Task 2 はこの `finishButton` に紐づく `pomodoro#finish` を変更する。

- [ ] **Step 1: 失敗するテストを書く**

`spec/system/activity_records_spec.rb` の 54〜65 行目（`it "スタートボタンと終了するボタンが表示されること"` と `it "スタートせずに「終了する」をクリックするとアラートが表示されること"` の 2 つ）を、以下の 3 つの `it` で丸ごと置き換える。

```ruby
    it "スタートボタンとキャンセルボタンが表示され、終了するボタンは表示されないこと" do
      aggregate_failures do
        expect(page).to have_button("スタート", visible: true)
        expect(page).to have_link("キャンセル", visible: true)
        # Capybara.ignore_hidden_elements = false なので visible: true の明示が要る
        expect(page).to have_no_button("終了する", visible: true)
        expect(page).to have_selector('[data-pomodoro-target="finishButton"].hidden', visible: :all)
      end
    end

    it "キャンセルをクリックするとマイページへ戻ること" do
      click_on "キャンセル", visible: true

      aggregate_failures do
        expect(page).to have_current_path(mypage_path, ignore_query: true)
        expect(user.activity_records.count).to eq(0)
      end
    end

    it "スタートせずにモチベーション画面の「それでいいもん」をクリックするとアラートが表示されること" do
      click_on "集中できない、やる気が出ないときは", visible: true
      expect(page).to have_selector('[data-pomodoro-target="motivationScreen"]:not(.hidden)')

      accept_alert("スタートボタンを押してください") do
        click_on "それでいいもん", visible: true
      end
    end
```

3 つ目は元の :61 のテストを**経路だけ付け替えた**もの。「終了する」は未スタート時に存在しなくなるが、モチベーション画面はスタート前でも開けるためアラート自体は残る（`_motivation_button.html.erb` は作業画面に常時レンダリングされている）。

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `docker compose exec web bundle exec rspec spec/system/activity_records_spec.rb -e "ポモドーロタイマー画面"`

Expected: FAIL 2 件。1 つ目は `have_link("キャンセル", visible: true)` が見つからず失敗、2 つ目は `click_on "キャンセル"` が `Capybara::ElementNotFound` で失敗。3 つ目は現状の実装でもパスする（既存の `finish()` のガードがそのまま効くため）。

- [ ] **Step 3: ビューに「キャンセル」を追加し「終了する」を初期非表示にする**

`app/views/activity_records/pomodoro/_timer_buttons.html.erb` の全体を以下に置き換える。

```erb
<div class="flex justify-center gap-6">

  <button type="button" data-pomodoro-target="startButton" data-action="click->pomodoro#start" class="bg-green-700 text-white/90 px-6 py-2 rounded-full hover:bg-green-800 transition duration-200">
    スタート
  </button>

  <%# スタート前だけの出口。まだ計測データが無く失うものがないので確認は挟まない。
      浄化タイマー画面（purification_times/show）の idle / paused と同じ作法。 %>
  <%= link_to t("shared.buttons.cancel"), mypage_path, data: { pomodoro_target: "cancelButton" }, class: "bg-red-500 text-white/90 px-6 py-2 rounded-full hover:bg-red-600 transition duration-200" %>

  <%# 初期状態はマークアップを正とする（connect() で消すとチラつく）。
      初回スタート時に JS が hidden を外し、以降は隠さない。 %>
  <button type="submit" data-pomodoro-target="finishButton" data-action="click->pomodoro#finish" class="hidden bg-red-500 text-white/90 px-6 py-2 rounded-full hover:bg-red-600 transition duration-200">
    終了する
  </button>

</div>
```

- [ ] **Step 4: Stimulus コントローラに targets を追加する**

`app/javascript/controllers/pomodoro_controller.js:6` の `static targets` に `cancelButton` と `finishButton` を足す。

```js
  static targets = ["workScreen", "breakScreen", "motivationScreen", "display", "savedTask", "taskInput", "startButton", "cancelButton", "finishButton", "pomodoroCount"]
```

- [ ] **Step 5: 初回スタート時に出口を入れ替える**

`start()` の中の「初回のみ」ブロック（`if (this.firstStartedAt === null) { ... }`）の末尾、`this.startActivityLock()` の直後に 3 行足す。**ブロックの外に出さないこと** — `isPurificationCounting()` のガードに引っかかった場合はその手前で `location.replace` するため、ブロック外に置くと「計測を開始していないのにキャンセルだけ消える」状態になる。

```js
      this.firstStartedAt = new Date()
      // ✅ 離脱警告を有効化
      this.addBeforeUnloadListener()
      // ✅ ここから活動記録の登録完了までを「光の時間の活動中」とし、浄化タイマーを排他する
      this.startActivityLock()

      // ✅ 計測データが生まれたので出口を入れ替える。以降キャンセルは戻さない
      //（休憩明けの作業画面ではスタートと終了するが並ぶ）。
      this.cancelButtonTarget.classList.add("hidden")
      this.finishButtonTarget.classList.remove("hidden")
    }
```

- [ ] **Step 6: JS をビルドしてテストを実行し、パスを確認**

Run: `docker compose exec web yarn build && docker compose exec web bundle exec rspec spec/system/activity_records_spec.rb -e "ポモドーロタイマー画面"`

Expected: PASS（`docker compose up` で起動中なら esbuild watcher がリビルド済みなので `yarn build` は省略可）

- [ ] **Step 7: 「終了する」の表示が既存テストで壊れていないことを確認**

Run: `docker compose exec web bundle exec rspec spec/system/activity_records_spec.rb spec/system/timer_exclusion_spec.rb`

Expected: PASS。スタート後に `finishButton` の `hidden` が外れるので、`:140`（休憩画面）`:204` `:227`（終了フロー）`timer_exclusion_spec.rb:144` の `click_on "終了する", visible: true` はいずれもそのまま通る。落ちる場合は Step 5 の位置（初回ブロックの内側か）を疑うこと。

- [ ] **Step 8: 「使い方」ページの文言を差し替える**

`app/views/static_pages/how_to_use/_step3.html.erb:37-39` を置き換える。この導線をキャンセルボタンが担うようになったため。

置き換え前:

```erb
    <p class="mb-2 text-md text-red-700">
      ※ 誤ってこの画面に来た／光の時間での行動が違う場合は、ブラウザの戻るボタンで戻りましょう。
    </p>
```

置き換え後:

```erb
    <p class="mb-2 text-md text-red-700">
      ※ 誤ってこの画面に来た／光の時間での行動が違う場合は、キャンセルボタンでマイページに戻りましょう。
    </p>
```

- [ ] **Step 9: RuboCop を実行**

Run: `docker compose exec web bin/rubocop`

Expected: no offenses

- [ ] **Step 10: コミット**

```bash
git add app/views/activity_records/pomodoro/_timer_buttons.html.erb \
        app/javascript/controllers/pomodoro_controller.js \
        app/views/static_pages/how_to_use/_step3.html.erb \
        spec/system/activity_records_spec.rb
git commit -m "feat: ポモドーロ画面の未スタート時の出口をキャンセルボタンにする #263"
```

---

### Task 2: 「終了する」に確認ダイアログを挟む

**Files:**
- Modify: `app/javascript/controllers/pomodoro_controller.js:311-331`（`finish()` を 3 メソッドに分割）
- Modify: `app/views/activity_records/pomodoro/_motivation_screen.html.erb`（「それでいいもん」の `data-action`）
- Test: `spec/system/activity_records_spec.rb:204-232`, `spec/system/timer_exclusion_spec.rb:143-145`

**Interfaces:**
- Consumes: Task 1 で追加した `finishButton` ターゲット（`click->pomodoro#finish`）、既存の `this.firstStartedAt` / `this.timerInterval` / `saveActivityRecord(lastEndedAt)` / `removeBeforeUnloadListener()`
- Produces: `finish()`（引数なし・確認あり）、`giveUp()`（引数なし・確認なし）、`completeSession(lastEndedAt)`（`Date` を受け取り、未スタートならアラートして中断、そうでなければ計測を止めて `/activity_records/new?...` へ遷移）

- [ ] **Step 1: 失敗するテストを書く（確認あり・確認なしの両方）**

`spec/system/activity_records_spec.rb` の `describe "終了ボタンをクリックしたとき"` 内、`context "作業画面から終了したとき"`（203〜216 行）を以下で置き換える。`it` を 1 つ追加している。

```ruby
      context "作業画面から終了したとき" do
        it "スタート後に終了すると確認ダイアログを経て新規作成画面へ遷移すること" do
          click_on "スタート", visible: true
          # スタート直後はタイマーが動いているので startButton が hidden になることを確認
          expect(page).to have_selector('[data-pomodoro-target="startButton"].hidden', wait: 5)

          accept_confirm("終了してよろしいでしょうか？") do
            within('[data-pomodoro-target="workScreen"]') do
              click_on "終了する", visible: true
            end
          end

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end

        it "確認ダイアログをキャンセルするとタイマーが継続すること" do
          click_on "スタート", visible: true
          expect(page).to have_selector('[data-pomodoro-target="startButton"].hidden', wait: 5)

          dismiss_confirm("終了してよろしいでしょうか？") do
            within('[data-pomodoro-target="workScreen"]') do
              click_on "終了する", visible: true
            end
          end

          aggregate_failures do
            # 遷移していないこと
            expect(page).to have_current_path(pomodoro_timer_activity_records_path, ignore_query: true)
            # タイマーが生きていれば、作業時間（この context では 3 秒）の満了で
            # 休憩画面へ切り替わる。clearInterval されていればここで止まったままになる。
            expect(page).to have_selector('[data-pomodoro-target="breakScreen"]:not(.hidden)', wait: 10)
            expect(page).to have_content("ポモドーロ数：1", wait: 10)
          end
        end
      end
```

「タイマーが継続していること」を `startButton` の hidden で見ないのが要点。この context は `before` で作業 3 秒・休憩 2 秒に短縮しているため、5 秒後には休憩明けで `startButton` が戻ってしまい、時間に依存した不安定なテストになる。**休憩画面へ切り替わったこと自体**が「`setInterval` が生き残った」ことの直接の証拠になる。

続けて `context "休憩画面から終了したとき"` の `it`（225〜231 行）の中身を `accept_confirm` で包む。

```ruby
        it "新規作成画面へ遷移すること" do
          accept_confirm("終了してよろしいでしょうか？") do
            within('[data-pomodoro-target="breakScreen"]') do
              click_on "終了する", visible: true
            end
          end

          expect(page).to have_current_path(new_activity_record_path, ignore_query: true, wait: 10)
        end
```

`context "モチベーション画面の「それでいいもん」をクリックしたとき"`（234〜248 行）は**変更しない**。確認ダイアログを出さない仕様なので、現行のテストがそのまま「確認が出ないこと」の証拠になる（`accept_confirm` で包んでいないため、ダイアログが出れば遷移せず失敗する）。

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `docker compose exec web bundle exec rspec spec/system/activity_records_spec.rb -e "終了ボタンをクリックしたとき"`

Expected: FAIL 3 件。`accept_confirm` / `dismiss_confirm` はダイアログが出ないと `Capybara::ModalNotFound` を投げる。

- [ ] **Step 3: `finish()` を 3 つのメソッドに分割する**

`app/javascript/controllers/pomodoro_controller.js` の現行 `finish()`（311〜331 行）を以下で置き換える。

```js
  // 「終了する」（作業画面・休憩画面）から呼ばれる。確認を取ってから終了する。
  finish() {
    // ✅ 確認ダイアログで迷っていた時間を活動時間に加算しないよう、押した瞬間を先に取る
    const lastEndedAt = new Date()

    // ✅ 確認は必ず副作用より前に通す。clearInterval の後ろに置くと、
    //    キャンセルした時にタイマーだけ止まって画面が残るという壊れ方をする。
    if (!window.confirm("終了してよろしいでしょうか？")) return

    this.completeSession(lastEndedAt)
  }

  // モチベーション画面「それでいいもん」から呼ばれる。あの画面自体が
  // 「本当にそれでいいですか？」と確認を兼ねているので、二重に確認しない。
  giveUp() {
    this.completeSession(new Date())
  }

  // 計測を止めて活動記録フォームへ遷移する。finish() / giveUp() の共通処理。
  completeSession(lastEndedAt) {
    // ✅ モチベーション画面はスタート前でも開けるため、giveUp() 経由で
    //    未スタートのままここへ来ることがある。外すと差分計算が NaN になる。
    if (!this.firstStartedAt) {
      alert("スタートボタンを押してください")
      return
    }

    if (this.timerInterval) {
      clearInterval(this.timerInterval)
      this.timerInterval = null
    }

    // ✅ タイマー終了時に離脱警告を無効化
    this.removeBeforeUnloadListener()

    // ✅ 最初のスタート時刻からの差分を計算
    const params = this.saveActivityRecord(lastEndedAt)
    // ✅ 確認フォーム画面に遷移
    location.replace(`/activity_records/new?${params.toString()}`)
  }
```

ネイティブ `confirm()` は JS の実行を止めるが、このコントローラの残り時間は `endedAt` からの差分計算（`startTimer()` 参照）なので、ダイアログを閉じた後も表示はズレない。

- [ ] **Step 4: 「それでいいもん」を `giveUp` に付け替える**

`app/views/activity_records/pomodoro/_motivation_screen.html.erb` の最後のボタンの `data-action` を変更する。

置き換え前:

```erb
    <button type="submit" data-action="click->pomodoro#finish" class="bg-red-500 text-lg px-8 py-2 rounded-full hover:bg-red-600 transition duration-200">
      それでいいもん
    </button>
```

置き換え後:

```erb
    <%# この画面が「本当にそれでいいですか？」と確認を兼ねているので、
        finish() ではなく確認なしの giveUp() を呼ぶ。 %>
    <button type="submit" data-action="click->pomodoro#giveUp" class="bg-red-500 text-lg px-8 py-2 rounded-full hover:bg-red-600 transition duration-200">
      それでいいもん
    </button>
```

- [ ] **Step 5: JS をビルドしてテストを実行し、パスを確認**

Run: `docker compose exec web yarn build && docker compose exec web bundle exec rspec spec/system/activity_records_spec.rb`

Expected: PASS（Task 1 で書き換えた「スタートせずに…それでいいもん…アラート」も、ガードが `completeSession()` に移っただけなので通り続ける）

- [ ] **Step 6: 排他制御のテストに `accept_confirm` を足す**

`spec/system/timer_exclusion_spec.rb:143-145` を置き換える。

置き換え前:

```ruby
      within('[data-pomodoro-target="workScreen"]') do
        click_on "終了する", visible: true
      end
```

置き換え後:

```ruby
      accept_confirm("終了してよろしいでしょうか？") do
        within('[data-pomodoro-target="workScreen"]') do
          click_on "終了する", visible: true
        end
      end
```

- [ ] **Step 7: 排他制御のテストを実行**

Run: `docker compose exec web bundle exec rspec spec/system/timer_exclusion_spec.rb`

Expected: PASS

- [ ] **Step 8: RuboCop を実行**

Run: `docker compose exec web bin/rubocop`

Expected: no offenses

- [ ] **Step 9: コミット**

```bash
git add app/javascript/controllers/pomodoro_controller.js \
        app/views/activity_records/pomodoro/_motivation_screen.html.erb \
        spec/system/activity_records_spec.rb \
        spec/system/timer_exclusion_spec.rb
git commit -m "feat: ポモドーロの「終了する」に終了確認ダイアログを追加する #263"
```

---

### Task 3: 全体検証

**Files:**
- 変更なし（検証のみ。失敗が出た場合のみ該当ファイルを修正）

**Interfaces:**
- Consumes: Task 1 / Task 2 の全変更
- Produces: なし

- [ ] **Step 1: アセットをビルドする**

Run: `docker compose exec web yarn build && docker compose exec web bin/rails tailwindcss:build`

Expected: どちらも正常終了（CI と同じ順序）

- [ ] **Step 2: テストスイート全体を実行**

Run: `docker compose exec web bundle exec rspec`

Expected: 全件 PASS。失敗した場合は `tmp/screenshots` のスクリーンショットを確認する。

- [ ] **Step 3: RuboCop と Brakeman を実行**

Run: `docker compose exec web bin/rubocop && docker compose exec web bin/brakeman --no-pager`

Expected: どちらも警告なし

- [ ] **Step 4: 完了条件を目視で確認する**

`docker compose up` した状態で `/activity_records/pomodoro_timer` を開き、issue #263 の完了条件を上から順に確認する。

1. 画面を開いた直後は「スタート」＋「キャンセル」が表示され、「終了する」は表示されない
2. 「キャンセル」でマイページへ戻る（確認なし）
3. 「スタート」押下後は「終了する」が表示され、「キャンセル」は消える
4. 休憩明けの作業画面で「スタート」と「終了する」が並ぶ（`work_duration` / `break_duration` を短くして確認すると速い）
5. 作業画面・休憩画面のどちらの「終了する」でも確認ダイアログが出る
6. モチベーション画面の「それでいいもん」では確認ダイアログが出ない
7. 確認をキャンセルするとタイマーがそのまま継続する
8. `/how_to_use` の step3 の文言が「キャンセルボタンでマイページに戻りましょう」になっている

- [ ] **Step 5: コードレビューを通す**

Run: `/code-review`

Expected: 指摘があれば対応してから次へ進む。

- [ ] **Step 6: プッシュして PR を作成する**

```bash
git push -u origin feature/pomodoro-cancel-button-263
gh pr create --title "ポモドーロタイマー画面にキャンセルボタンと終了確認を追加する" --body "Closes #263"
```
