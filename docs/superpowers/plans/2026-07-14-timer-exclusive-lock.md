# ポモドーロタイマーと浄化タイマーの排他制御 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 光の時間の活動（ポモドーロ計測〜活動記録の登録完了）と浄化タイマーが、同一ブラウザの別タブで同時に走らないようにする。

**Architecture:** 2 つの非対称なガードを組む。(A) 浄化タイマーはサーバに状態があるので、サーバ側 `before_action` でポモドーロ画面を弾く。ただし「時間切れなのに status が running のまま残る」永久ロックを避けるため、実時間から導出する `PurificationTime#counting?` を新設して条件に使う。(B) ポモドーロはクライアントにしか状態が無く終了シグナルも無いので、`localStorage` の**期限付きリース**（TTL 3 分 / heartbeat 30 秒）で表す。更新が止まれば勝手に腐るため、ブラウザバック・タブ閉じ・記録せず離脱を区別するコードを一行も書かない。TTL が長いのは、ブラウザが非表示タブの `setInterval` を 1 分に 1 回まで絞るため（Chrome の intensive throttling）。離脱時は `pagehide` でロックを削除せず期限を 5 秒に詰めるだけにし、正常遷移なら遷移先が更新して復活、本当の離脱なら 5 秒で腐る。これが PR #88（`User#current_mode` を明示クリアする設計）が破綻した原因を構造的に取り除く。

**Tech Stack:** Rails 8.1 / Stimulus (Hotwire) / esbuild / RSpec + Capybara + Selenium

設計書: `docs/superpowers/specs/2026-07-14-timer-exclusive-lock-design.md`
関連 issue: #87

## Global Constraints

- DB マイグレーションは行わない。**新しいカラムは 1 つも追加しない。**
- UI 文字列・フラッシュメッセージ・コメントはすべて日本語。i18n キーは `config/locales/views/ja.yml` に追加する。
- Ruby は RuboCop（`rubocop-rails-omakase` + ダブルクォート強制）に通ること。`spec/**/*` もダブルクォート。
- テストは RSpec。全コマンドは `docker compose exec web` 経由で実行する。
- `localStorage` キーは `gtt:activity_lock`、`sessionStorage` キーは `gtt:tab_id`。TTL は 180000 ms、heartbeat は 30000 ms、離脱時の猶予は 5000 ms。この値は `app/javascript/lib/activity_lock.js` にのみ定義し、他ファイルで再定義しない。
- 排他制御のために本来の機能を壊さない。`localStorage` が例外を投げる環境では「ロックは無い」ものとして通常どおり動作させる。
- 作業ブランチは `feature/exclusive-timer-lock-87`（作成済み）。コミットメッセージ末尾に ` #87` を含める。

---

### Task 1: `PurificationTime#counting?` — 実時間ベースの「計測中」判定

**Files:**
- Modify: `app/models/purification_time.rb`
- Test: `spec/models/purification_time_spec.rb`

**Interfaces:**
- Consumes: なし
- Produces: `PurificationTime#counting?` → `true` / `false`。Task 2 のサーバ側ガードが使う。

このタスクが最重要である。既存の `running?` は `status` カラムを見るだけで、時間切れの検知は JS が `stop!` を呼ぶことに依存している。タブを閉じたまま時間切れになると `status` は `running` のまま残るため、`running?` をロック条件にすると**ユーザーが永久にポモドーロを開始できなくなる**。

- [ ] **Step 1: 失敗するテストを書く**

`spec/models/purification_time_spec.rb` の末尾（最後の `end` の直前）に追加する。

```ruby
  describe "#counting?" do
    let(:user) { create(:user) }

    context "idle のとき" do
      let(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

      it "false を返すこと" do
        expect(purification_time.counting?).to be false
      end
    end

    context "paused のとき" do
      let(:purification_time) { create(:purification_time, :paused, user: user) }

      it "false を返すこと（残り時間を保持して止まっているだけで、計測はしていない）" do
        expect(purification_time.counting?).to be false
      end
    end

    context "running かつ終了時刻を過ぎていないとき" do
      let(:purification_time) { create(:purification_time, :running, user: user) }

      it "true を返すこと" do
        travel_to(5.minutes.from_now) do
          expect(purification_time.counting?).to be true
        end
      end
    end

    context "running のまま終了時刻を過ぎているとき" do
      let(:purification_time) { create(:purification_time, :running, user: user) }

      it "false を返すこと（タブを閉じたまま時間切れになり stop! が呼ばれなかったケース。ここで true を返すと永久ロックになる）" do
        travel_to(11.minutes.from_now) do
          expect(purification_time.counting?).to be false
        end
      end
    end

    context "running だが started_at が nil のとき" do
      let(:purification_time) { create(:purification_time, :running, user: user, started_at: nil) }

      it "false を返すこと（不正なデータで例外を出さない）" do
        expect(purification_time.counting?).to be false
      end
    end
  end
```

`:running` トレイトは `total_time { 600 }`（10 分）・`started_at { Time.current }` なので、5 分後は計測中、11 分後は時間切れになる。`ActiveSupport::Testing::TimeHelpers` は `spec/rails_helper.rb` でグローバルに include 済みなので、`travel_to` はそのまま使える。

- [ ] **Step 2: テストを実行して失敗を確認する**

```bash
docker compose exec web bundle exec rspec spec/models/purification_time_spec.rb -e "#counting?"
```

Expected: FAIL — `NoMethodError: undefined method 'counting?'`

- [ ] **Step 3: 最小の実装を書く**

`app/models/purification_time.rb` の `finished?` の直後に追加する。

```ruby
  # 実時間ベースで「いま計測中か」を導出する。status だけを見ると、時間切れ後に
  # stop! が呼ばれないまま（タブを閉じた等）running が残り、ポモドーロを永久に
  # ブロックしてしまうため、排他制御の判定にはこちらを使う。
  def counting?
    running? && started_at.present? && Time.current < started_at + total_time
  end
```

- [ ] **Step 4: テストを実行して通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/models/purification_time_spec.rb
```

Expected: PASS（既存のテストも含めて全て緑）

- [ ] **Step 5: コミット**

```bash
git add app/models/purification_time.rb spec/models/purification_time_spec.rb
git commit -m "feat: 実時間ベースで計測中を判定する PurificationTime#counting? を追加 #87"
```

---

### Task 2: サーバ側ガード — 浄化タイマー計測中はポモドーロ画面に入れない

**Files:**
- Modify: `app/controllers/activity_records_controller.rb`
- Modify: `config/locales/views/ja.yml`
- Test: `spec/requests/activity_records_spec.rb`

**Interfaces:**
- Consumes: `PurificationTime#counting?`（Task 1）
- Produces: i18n キー `activity_records.flash_message.purification_time_counting`

- [ ] **Step 1: 失敗するテストを書く**

`spec/requests/activity_records_spec.rb` の末尾（最後の `end` の直前）に追加する。

```ruby
  describe "GET /activity_records/pomodoro_timer 浄化タイマーとの排他制御" do
    let(:user) { create(:user) }
    let!(:light_time) { create(:light_time, :current, user: user) }
    let!(:dark_time) { create(:dark_time, user: user) }

    before { sign_in user }

    context "浄化タイマーが計測中のとき" do
      let!(:purification_time) { create(:purification_time, :running, user: user) }

      it "マイページへリダイレクトし、アラートを表示すること" do
        get pomodoro_timer_activity_records_path

        aggregate_failures do
          expect(response).to redirect_to(mypage_path)
          expect(flash[:alert]).to eq "浄化タイマーの実行中はポモドーロタイマーを開始できません"
        end
      end
    end

    context "浄化タイマーが running のまま時間切れになっているとき" do
      let!(:purification_time) { create(:purification_time, :running, user: user) }

      it "ポモドーロ画面を表示すること（永久ロックさせない）" do
        travel_to(11.minutes.from_now) do
          get pomodoro_timer_activity_records_path
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context "浄化タイマーが一時停止中のとき" do
      let!(:purification_time) { create(:purification_time, :paused, user: user) }

      it "ポモドーロ画面を表示すること" do
        get pomodoro_timer_activity_records_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "浄化タイマーが存在しないとき" do
      it "ポモドーロ画面を表示すること" do
        get pomodoro_timer_activity_records_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
```

`spec/requests/activity_records_spec.rb` の既存の `let` / `sign_in` の書き方と重複しても構わない。この `describe` ブロック内で完結させること。

- [ ] **Step 2: テストを実行して失敗を確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/activity_records_spec.rb -e "浄化タイマーとの排他制御"
```

Expected: FAIL — 「浄化タイマーが計測中のとき」で `expected response to redirect to mypage_path but was 200`

- [ ] **Step 3: i18n メッセージを追加する**

`config/locales/views/ja.yml` の `activity_records.flash_message` に 1 行足す。既存はこうなっている。

```yaml
  activity_records:
    flash_message:
      require_timer_access: ポモドーロタイマーからアクセスしてください
      require_both_times: 光の時間と闇の時間を設定してからタイマーを開始してください
```

`require_both_times` の下に追加する。

```yaml
      purification_time_counting: 浄化タイマーの実行中はポモドーロタイマーを開始できません
```

- [ ] **Step 4: コントローラにガードを実装する**

`app/controllers/activity_records_controller.rb` の `before_action` 群の末尾に 1 行足す。

```ruby
  before_action :ensure_purification_not_counting, only: %i[pomodoro_timer]
```

そして `private` 以下（`not_found_redirect_path` の直前）にメソッドを追加する。

```ruby
  # 浄化タイマーが実際に計測中の間は、光の時間の活動を開始させない。
  # 浄化タイマーはタブを閉じても走り続けるサーバ側の状態なので、この向きの
  # ガードはサーバで判定する（クライアントの localStorage では判定できない）。
  def ensure_purification_not_counting
    return unless current_user.purification_time&.counting?

    redirect_to mypage_path, alert: t("activity_records.flash_message.purification_time_counting")
  end
```

`purification_time` は `has_one` で未作成のことがあるため、必ず `&.` を使うこと。

- [ ] **Step 5: テストを実行して通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/activity_records_spec.rb
```

Expected: PASS（既存のテストも含めて全て緑）

- [ ] **Step 6: コミット**

```bash
git add app/controllers/activity_records_controller.rb config/locales/views/ja.yml spec/requests/activity_records_spec.rb
git commit -m "feat: 浄化タイマー計測中はポモドーロ画面へのアクセスを禁止 #87"
```

---

### Task 3: `activity_lock.js` — 期限付きリースのモジュール

**Files:**
- Create: `app/javascript/lib/activity_lock.js`

**Interfaces:**
- Consumes: なし
- Produces: 名前付きエクスポート 4 つ。Task 4 と Task 5 が使う。
  - `acquire() → Boolean` — 有効な他タブのロックが無ければ自分名義で取得し `true`。他タブが持っていれば何もせず `false`。
  - `renew() → void` — 自分が持ち主のときだけ期限を延ばす。
  - `release() → void` — 自分が持ち主のときだけ削除する。
  - `heldByOther() → Boolean` — 他タブが有効なロックを持っているか。期限切れは `false`。

本プロジェクトには JS のユニットテスト基盤が無いため、このモジュール単体のテストは書かない。振る舞いは Task 6 のシステム spec で検証する。**Task 3 単独では動作確認できないので、Task 4・5 と合わせて初めて緑になる。**

- [ ] **Step 1: モジュールを作成する**

`app/javascript/lib/activity_lock.js` を新規作成する。

```js
// 「光の時間の活動中（ポモドーロ計測〜活動記録の登録完了）」を表す、期限付きのリース。
//
// ポモドーロの状態はブラウザのメモリにしか無く、信頼できる終了シグナルが存在しない
// （ブラウザバック・タブ閉じ・記録せず離脱が、すべて「通知なき終了」になる）。
// そのため「明示的にクリアしないと消えないフラグ」で表すと、消し損ねた瞬間に
// ユーザーが恒久的にロックアウトされる。
//
// ここでは代わりに、更新され続けている間だけ生きているリースとして表す。
// 更新が止まれば勝手に腐るので、離脱の種類を区別するコードは一切書かない。

const LOCK_KEY = "gtt:activity_lock"
const TAB_KEY = "gtt:tab_id"

// ブラウザは非表示タブの setInterval を絞る。Chrome は 5 分ほど隠れたタブの
// タイマーを「1 分に 1 回」まで落とす（intensive throttling）。
// ポモドーロ中に別タブへ切り替えるのはまさにこの機能が想定している状況なので、
// heartbeat が 1 分に 1 回まで落ちてもリースが切れない値を選ぶ必要がある。
// TTL を数秒に設定すると、25 分のセッションのうち最初の 5 分しか排他が効かない。
export const TTL_MS = 180000        // ロックの有効期間（3 分）
export const HEARTBEAT_MS = 30000   // 更新間隔（30 秒）。絞られて 1 分間隔になっても TTL に届く

// 離脱時にリースへ与える猶予。削除ではなく期限の短縮にとどめるのが要点。
// 「本当の離脱」と「フォームへの正常遷移」を区別しないまま、両方を正しく扱える:
//   - 正常遷移なら、遷移先のページが 1 秒以内に renew() して満了期限が戻る
//   - 本当の離脱なら、誰も更新しないので数秒で腐って消える
// 削除してしまうと遷移中の一瞬だけロックが空き、その隙に他タブが入れてしまう。
const ORPHAN_TTL_MS = 5000

// タブの同一性。sessionStorage はタブ単位で、同一タブ内のページ遷移では保持され、
// 別タブには引き継がれない。だからポモドーロ画面 → 活動記録フォームへ遷移しても
// 「同じ持ち主」としてリースを引き継げる。
function tabId() {
  let id = sessionStorage.getItem(TAB_KEY)
  if (!id) {
    id = `${Date.now()}-${Math.random().toString(36).slice(2)}`
    sessionStorage.setItem(TAB_KEY, id)
  }
  return id
}

// 現在有効なロックを返す。期限切れのロックは「無い」ものとみなす（掃除役は不要）。
function currentLock() {
  const raw = localStorage.getItem(LOCK_KEY)
  if (!raw) return null

  const lock = JSON.parse(raw)
  if (!lock || typeof lock.expiresAt !== "number") return null
  if (lock.expiresAt <= Date.now()) return null

  return lock
}

function write() {
  localStorage.setItem(
    LOCK_KEY,
    JSON.stringify({ owner: tabId(), expiresAt: Date.now() + TTL_MS })
  )
}

// プライベートモード等で Storage が例外を投げても、排他制御のために本来の機能を
// 壊さない。その場合は「ロックは無い」ものとして通常どおり動かす。
function safely(fn, fallback) {
  try {
    return fn()
  } catch {
    return fallback
  }
}

export function acquire() {
  return safely(() => {
    const lock = currentLock()
    if (lock && lock.owner !== tabId()) return false

    write()
    return true
  }, true)
}

export function renew() {
  safely(() => {
    const lock = currentLock()
    if (lock && lock.owner !== tabId()) return

    write()
  }, undefined)
}

export function release() {
  safely(() => {
    const lock = currentLock()
    if (lock && lock.owner !== tabId()) return

    localStorage.removeItem(LOCK_KEY)
  }, undefined)
}

export function heldByOther() {
  return safely(() => {
    const lock = currentLock()
    return Boolean(lock) && lock.owner !== tabId()
  }, false)
}

// このタブが離脱する（タブを閉じる / ブラウザバック / 遷移）ときに、自分のロックの
// 期限を短く詰める。すでに ORPHAN_TTL_MS より近い期限なら触らない。
export function orphan() {
  safely(() => {
    const lock = currentLock()
    if (!lock || lock.owner !== tabId()) return

    const expiresAt = Math.min(lock.expiresAt, Date.now() + ORPHAN_TTL_MS)
    localStorage.setItem(LOCK_KEY, JSON.stringify({ owner: lock.owner, expiresAt }))
  }, undefined)
}

// このモジュールを読み込むページは、離脱時に必ず自分のロックを orphan する。
// pagehide は離脱の種類（タブ閉じ・ブラウザバック・通常遷移）を問わず発火するが、
// ここでは区別しないことが正しい。区別を始めた瞬間に、明示的な後始末に依存する
// 設計へ逆戻りし、後始末を取りこぼしたユーザーが締め出される。
window.addEventListener("pagehide", orphan)
```

`currentLock()` の `JSON.parse` は壊れた値で例外を投げうるが、呼び出し元がすべて `safely` で包んでいるため、フォールバック値に落ちる。

- [ ] **Step 2: ビルドが通ることを確認する**

```bash
docker compose exec web yarn build
```

Expected: エラーなく完了する（この時点ではまだどこからも import されていない）

- [ ] **Step 3: コミット**

```bash
git add app/javascript/lib/activity_lock.js
git commit -m "feat: 光の時間の活動を表す期限付きリースのモジュールを追加 #87"
```

---

### Task 4: `activity_lock_controller.js` — ガードと保持を画面に貼る

**Files:**
- Create: `app/javascript/controllers/activity_lock_controller.js`
- Modify: `app/javascript/controllers/index.js`
- Modify: `app/views/purification_times/show.html.erb`
- Modify: `app/views/activity_records/pomodoro_timer.html.erb`
- Modify: `app/views/activity_records/new.html.erb`
- Modify: `app/controllers/mypages_controller.rb`
- Modify: `app/views/mypages/show.html.erb`
- Modify: `config/locales/views/ja.yml`

**Interfaces:**
- Consumes: `acquire()` / `renew()` / `heldByOther()` / `HEARTBEAT_MS`（Task 3）
- Produces: Stimulus コントローラ `activity-lock`。値は `hold: Boolean` と `redirectTo: String`。

- [ ] **Step 1: Stimulus コントローラを作成する**

`app/javascript/controllers/activity_lock_controller.js` を新規作成する。

`release` という名前の Stimulus アクションを公開するが、モジュール側の `release` と名前が衝突して自己再帰になるため、import には別名を付けること。

```js
import { Controller } from "@hotwired/stimulus"
import { acquire, renew, release as releaseLock, heldByOther, HEARTBEAT_MS } from "../lib/activity_lock"

// 「光の時間の活動」リースを画面に貼るための薄いコントローラ。
//
//   hold:       true なら connect 時にロックを取り、以後 heartbeat で更新し続ける
//   redirectTo: 他タブがロックを持っていたら、この URL へ引き返す
//
// Connects to data-controller="activity-lock"
export default class extends Controller {
  static values = {
    hold: { type: Boolean, default: false },
    redirectTo: { type: String, default: "" }
  }

  connect() {
    // localStorage の読み取りは同期なので、判定とリダイレクトは connect と
    // 同じティックで走る。画面のちらつきはほぼ発生しない。
    if (this.redirectToValue && heldByOther()) {
      location.replace(this.redirectToValue)
      return
    }

    if (this.holdValue) {
      acquire()
      this.heartbeat = setInterval(() => renew(), HEARTBEAT_MS)
    }
  }

  // 活動記録フォームの送信時に呼ぶ（Task 5 で form に data-action を貼る）。
  // 登録が完了すればロックは不要なので、TTL を待たずに解放する。
  // バリデーションエラーで new が再描画された場合は connect が再度 acquire するので、
  // 送信が失敗しても壊れない。
  release() {
    releaseLock()
    clearInterval(this.heartbeat)
  }

  disconnect() {
    // ここで releaseLock() は呼ばない。離脱の種類（ブラウザバック / タブ閉じ /
    // 正常遷移）を区別し始めた瞬間に、PR #88 と同じ破綻が戻ってくる。
    // 更新が止まればリースは TTL で勝手に腐る。
    clearInterval(this.heartbeat)
  }
}
```

- [ ] **Step 2: Stimulus に登録する**

`app/javascript/controllers/index.js` の末尾に追加する。

```js
import ActivityLockController from "./activity_lock_controller"
application.register("activity-lock", ActivityLockController)
```

- [ ] **Step 3: 浄化タイマー画面にガードを貼る**

`app/views/purification_times/show.html.erb` の先頭の `<div data-controller="purification-timer" ...>` を、コントローラ 2 つを持つように書き換える。Stimulus は `data-controller` にスペース区切りで複数指定できる。

変更前:

```erb
<div
  data-controller="purification-timer"
  data-purification-timer-remaining-value="<%= @purification_time.remaining_time %>"
```

変更後:

```erb
<div
  data-controller="purification-timer activity-lock"
  data-activity-lock-redirect-to-value="<%= mypage_path(locked: "activity") %>"
  data-purification-timer-remaining-value="<%= @purification_time.remaining_time %>"
```

以降の行はそのまま。`hold` は指定しない（この画面はロックを持たない）。

- [ ] **Step 4: ポモドーロ画面にガードを貼る**

`app/views/activity_records/pomodoro_timer.html.erb` の先頭を書き換える。ここもガードのみで、保持は Task 5 で `pomodoro_controller` が行う。これにより「光の時間の活動は 1 つだけ」（issue #87 の 3 項目目）も満たされる。

変更前:

```erb
<div data-controller="pomodoro"
     data-pomodoro-work-duration-value="<%= @pomodoro_setting.work_duration * 60 %>"
```

変更後:

```erb
<div data-controller="pomodoro activity-lock"
     data-activity-lock-redirect-to-value="<%= mypage_path(locked: "activity") %>"
     data-pomodoro-work-duration-value="<%= @pomodoro_setting.work_duration * 60 %>"
```

- [ ] **Step 5: 活動記録フォームにロックの保持を貼る**

`app/views/activity_records/new.html.erb` の 2 行目の `<div>` に `data-controller` を足す。この画面は「ブロックする側」ではなく「ロックを持ち続ける側」なので `hold: true` のみで、`redirect_to` は指定しない。

変更前:

```erb
<div class="min-h-screen flex items-center justify-center bg-linear-to-b from-yellow-400 from-0% via-yellow-200 via-80% to-yellow-100 to-100% text-zinc-800">
```

変更後:

```erb
<div class="min-h-screen flex items-center justify-center bg-linear-to-b from-yellow-400 from-0% via-yellow-200 via-80% to-yellow-100 to-100% text-zinc-800"
     data-controller="activity-lock"
     data-activity-lock-hold-value="true">
```

- [ ] **Step 6: マイページで追い返しの理由を表示できるようにする**

浄化タイマー画面からのリダイレクトはクライアント発なので Rails の flash が使えない。`?locked=activity` を受けてマイページ側でメッセージを出す。

まず `config/locales/views/ja.yml` の `mypages` セクションに `flash_message` を追加する。既存はこうなっている。

```yaml
  mypages:
    show:
      title: マイページ
```

これを次のように書き換える。

```yaml
  mypages:
    flash_message:
      activity_locked: 別のタブで光の時間の活動を実行中です
    show:
      title: マイページ
```

次に `app/controllers/mypages_controller.rb` の `show` の末尾に 1 行足す。

```ruby
class MypagesController < ApplicationController
  def show
    @dark_time = current_user.dark_time
    @light_time = current_user.light_times.find_by(is_current: true) || current_user.light_times.first
    @purification_time = current_user.purification_time
    @today_light_time = ActivityRecord.total_light_time_today(current_user)
    @pomodoro_setting = current_user.pomodoro_setting

    # 別タブで光の時間の活動中だったため、クライアント側のガードに追い返された場合。
    # サーバの状態からは判定できないので、クエリパラメータで理由を受け取る。
    flash.now[:alert] = t("mypages.flash_message.activity_locked") if params[:locked] == "activity"
  end
end
```

- [ ] **Step 7: マイページで flash が描画されることを確認する**

マイページのレイアウトが flash を描画しているか確認する。

```bash
docker compose exec web grep -rn "flash" app/views/layouts/ app/views/shared/
```

`flash.each` 相当の描画（多くは `app/views/layouts/application.html.erb` または `shared/_flash_messages` 等のパーシャル）が既にあれば、追加作業は不要。無い場合のみ、マイページで `flash[:alert]` が表示されるようにすること。既存の `require_both_times` アラート（`redirect_to mypage_path, alert: ...`）がマイページで表示できている以上、描画箇所は必ず存在する。

- [ ] **Step 8: ビルドが通ることを確認する**

```bash
docker compose exec web yarn build && docker compose exec web bin/rubocop
```

Expected: どちらもエラーなく完了する

- [ ] **Step 9: コミット**

```bash
git add app/javascript/controllers/activity_lock_controller.js app/javascript/controllers/index.js app/views/purification_times/show.html.erb app/views/activity_records/pomodoro_timer.html.erb app/views/activity_records/new.html.erb app/controllers/mypages_controller.rb config/locales/views/ja.yml
git commit -m "feat: 光の時間の活動リースのガードと保持を各画面に適用 #87"
```

---

### Task 5: `pomodoro_controller.js` — スタート押下でロックを取り、submit で解放する

**Files:**
- Modify: `app/javascript/controllers/pomodoro_controller.js`
- Modify: `app/views/activity_records/new.html.erb`

**Interfaces:**
- Consumes: `acquire()` / `renew()` / `HEARTBEAT_MS`（Task 3）、Stimulus アクション `activity-lock#release`（Task 4）
- Produces: なし

ポモドーロ画面だけ保持のトリガーが特殊である。**画面表示ではなくスタート押下でロックを取る。** タイマー画面を開いて眺めているだけで浄化タイマーをロックしてしまうのを避けるためである。

- [ ] **Step 1: モジュールを import する**

`app/javascript/controllers/pomodoro_controller.js` の 1 行目の import の下に追加する。

変更前:

```js
import { Controller } from "@hotwired/stimulus"
```

変更後:

```js
import { Controller } from "@hotwired/stimulus"
import { acquire, renew, HEARTBEAT_MS } from "../lib/activity_lock"
```

`release` はここでは import しない。ポモドーロ画面はロックを解放しない（解放は活動記録フォームの送信時のみ）。

- [ ] **Step 2: スタート押下時にロックを取得する**

同ファイルの `start()`（68 行目付近）に手を入れる。既存の「最初のスタート時のみ記録」する分岐の中に入れることで、2 回目以降のスタート（休憩明けの再開など）で無駄に `acquire()` を呼ばない。

変更前:

```js
  start() {
    if (this.timerInterval) return

    // ✅ 最初のスタート時のみ記録
    if (this.firstStartedAt === null) {
      this.firstStartedAt = new Date()
      // ✅ 離脱警告を有効化
      this.addBeforeUnloadListener()
    }
```

変更後:

```js
  start() {
    if (this.timerInterval) return

    // ✅ 最初のスタート時のみ記録
    if (this.firstStartedAt === null) {
      this.firstStartedAt = new Date()
      // ✅ 離脱警告を有効化
      this.addBeforeUnloadListener()
      // ✅ ここから活動記録の登録完了までを「光の時間の活動中」とし、浄化タイマーを排他する
      this.startActivityLock()
    }
```

- [ ] **Step 3: ロックの保持メソッドを追加する**

同ファイルの `saveActivityRecord(lastEndedAt)` メソッドの直前に追加する。

```js
  // ✅ 光の時間の活動リースを取得し、以後 heartbeat で更新し続ける。
  // タイマー画面 → 活動記録フォームへの遷移は同一タブなので、遷移先の
  // activity-lock コントローラが同じリースをそのまま引き継いで更新する。
  startActivityLock() {
    acquire()
    this.lockHeartbeat = setInterval(() => renew(), HEARTBEAT_MS)
  }
```

- [ ] **Step 4: disconnect で heartbeat だけ止める**

`disconnect()`（54 行目付近）に 1 行足す。**`release()` は絶対に呼ばないこと。** ここで解放してしまうと、活動記録フォームへの正常遷移と離脱を区別する必要が生まれ、PR #88 の `isNavigatingToForm` 問題がそのまま再発する。

変更前:

```js
  disconnect() {
    // ✅ コントローラーが破棄される時にイベントリスナーを削除
    this.removeBeforeUnloadListener()

    if (this.timerInterval) {
      clearInterval(this.timerInterval)
    }
  }
```

変更後:

```js
  disconnect() {
    // ✅ コントローラーが破棄される時にイベントリスナーを削除
    this.removeBeforeUnloadListener()

    if (this.timerInterval) {
      clearInterval(this.timerInterval)
    }

    // ✅ heartbeat を止めるだけ。release() は呼ばない。
    // 離脱（ブラウザバック / タブ閉じ）とフォームへの正常遷移をここで区別し始めると
    // PR #88 と同じ破綻に戻る。更新が止まればリースは TTL で勝手に腐る。
    clearInterval(this.lockHeartbeat)
  }
```

- [ ] **Step 5: フォーム送信時にロックを解放する**

登録が完了すればロックは不要なので、TTL を待たずに解放する。Task 4 で `activity_lock_controller.js` に実装済みの `release` アクションを、フォームの submit から呼ぶ。

`app/views/activity_records/new.html.erb` の `form_with` に `data` を渡す。この `<div>` には Task 4 で `data-controller="activity-lock"` を貼ってあるため、内側のフォームからアクションを呼べる。

変更前:

```erb
    <%= form_with model: @form, url: activity_records_path, class: "space-y-4" do |f| %>
```

変更後:

```erb
    <%= form_with model: @form, url: activity_records_path, class: "space-y-4", data: { action: "submit->activity-lock#release" } do |f| %>
```

- [ ] **Step 6: ビルドが通ることを確認する**

```bash
docker compose exec web yarn build
```

Expected: エラーなく完了する

- [ ] **Step 7: コミット**

```bash
git add app/javascript/controllers/pomodoro_controller.js app/views/activity_records/new.html.erb
git commit -m "feat: ポモドーロのスタート押下でリースを取得し、記録の送信時に解放 #87"
```

---

### Task 6: システム spec — 2 タブでの排他を検証する

**Files:**
- Test: `spec/system/timer_exclusion_spec.rb`（新規）

**Interfaces:**
- Consumes: Task 1〜5 のすべて
- Produces: なし

`localStorage` は同一ブラウザセッションの全タブで共有されるため、Capybara の `open_new_window` / `within_window` で実際に再現できる。

- [ ] **Step 1: 失敗するテストを書く**

`spec/system/timer_exclusion_spec.rb` を新規作成する。

```ruby
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

      # リースが書き込まれるのを待つ
      expect(page).to have_no_button("スタート")

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
      expect(page).to have_no_button("スタート")

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
end
```

`click_button "スタート"` の後に `have_no_button("スタート")` を待つのは、`start()` が `startButtonTarget.classList.add("hidden")` を実行するためである。`Capybara.ignore_hidden_elements = false` が設定されているため `have_no_button` では消えたと判定できない可能性がある。その場合は代わりに次で待つこと。

```ruby
      expect(page).to have_css("[data-pomodoro-target='startButton'].hidden", visible: :all)
```

- [ ] **Step 2: テストを実行して通ることを確認する**

Task 1〜5 が完了していれば、このテストは最初から通るはずである（TDD の順序としては後追いだが、JS のユニットテスト基盤が無いためここでまとめて検証する）。

```bash
docker compose exec web yarn build
docker compose exec web bin/rails tailwindcss:build
docker compose exec web bundle exec rspec spec/system/timer_exclusion_spec.rb
```

Expected: PASS（4 example すべて緑）

失敗した場合は `tmp/screenshots/` のスクリーンショットを確認すること。特に「スタート押下後にリースが書き込まれる前に別タブが開いた」というタイミング問題が疑われる場合は、Step 1 の待機条件を見直す。

- [ ] **Step 3: 全テストと Lint を通す**

```bash
docker compose exec web bundle exec rspec
docker compose exec web bin/rubocop
docker compose exec web bin/brakeman --no-pager
```

Expected: すべて緑

- [ ] **Step 4: コミット**

```bash
git add spec/system/timer_exclusion_spec.rb
git commit -m "test: ポモドーロと浄化タイマーの排他制御のシステム spec を追加 #87"
```

---

## 完了後の手動確認

CI とテストだけでは拾えない、実際のブラウザでの体感を確認する。

1. `docker compose up` して 2 つのタブでログインする。
2. タブ A でポモドーロを開始 → タブ B で浄化タイマーを開く → マイページへ追い返され、理由が表示されること。
3. タブ A でタイマーを終了 → 活動記録フォームへ遷移 → **この状態でもタブ B から浄化タイマーに入れないこと**（PR #88 が落ちた箇所。リースが同一タブで引き継がれている証拠になる）。
4. タブ A で活動記録を登録 → 即座にタブ B から浄化タイマーに入れること（submit で解放しているため待たされない）。
5. タブ A でポモドーロ計測中に**ブラウザバック** → 5 秒待つ → タブ B から浄化タイマーに入れること（`pagehide` がリースの期限を詰め、腐って消えた証拠になる）。
6. タブ A でポモドーロ計測中に**タブごと閉じる** → 5 秒待つ → タブ B から浄化タイマーに入れること。
8. **タブ A でポモドーロを開始し、タブ B に切り替えて 6 分以上放置してから**タブ B で浄化タイマーを開く → 入れないこと。これがバックグラウンドタブのタイマー絞りに耐えている証拠になる。TTL が短いとここで入れてしまい、機能がセッションの大半で無効になる。
7. 浄化タイマーを開始してタブを閉じ、時間切れになる時刻を過ぎてからポモドーロ画面を開く → **入れること**（`counting?` が永久ロックを防いでいる証拠になる）。
