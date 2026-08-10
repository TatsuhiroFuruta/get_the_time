# ポモドーロタイマー画面のキャンセルボタンと終了確認 設計書

関連 issue: [#263](https://github.com/TatsuhiroFuruta/get_the_time/issues/263)

## 目的

ポモドーロタイマー画面に「まだ何も計測していないユーザーの出口」を用意し、計測中の誤クリックによる中断を防ぐ。

## 現状の問題

画面を開いた直後から「スタート」と「終了する」が並んでいる。この状態の「終了する」は押しても何も記録できず、`alert("スタートボタンを押してください")` が出るだけの行き止まりである。誤ってこの画面に来たユーザーには出口がなく、「使い方」ページは `※ 誤ってこの画面に来た／光の時間での行動が違う場合は、ブラウザの戻るボタンで戻りましょう。` と案内している。

一方で計測中は、確認なしのワンクリックで計測が終了して活動記録フォームへ遷移する。

## 既存パターンとの整合

浄化タイマー画面（`app/views/purification_times/show.html.erb`）には既に同じ形が実装されている。

```erb
<%# idle / paused %>  スタート ＋ キャンセル(link_to mypage_path)
<%# running %>        終了する
```

本設計は新しいパターンの発明ではなく、**ポモドーロ画面をこの既存の作法に揃えるもの**である。

## 状態とボタンの対応

| 状態 | スタート | キャンセル | 終了する |
|---|---|---|---|
| 画面を開いた直後（未スタート） | 表示 | **表示** | 非表示 |
| 計測中（作業画面） | 非表示 | 非表示 | **表示** |
| 休憩画面 | — | — | 表示（現状どおり） |
| 休憩明けの作業画面（2 セッション目以降） | 表示 | 非表示 | **表示** |

キャンセルは「まだ何も計測していない」ときだけの出口である。一度スタートしたら計測データが存在するので、以降の出口は必ず活動記録フォームを通る「終了する」に一本化される。

表の最下段は**追加コード不要で成立する**。「終了する」を一度表示したら隠さないだけで、`switchToWorkMode()` が再表示する「スタート」と自然に並ぶ。ここに専用の状態を持たせない。

## ビュー: `app/views/activity_records/pomodoro/_timer_buttons.html.erb`

- 「キャンセル」を `link_to t("shared.buttons.cancel"), mypage_path` で追加し、`data-pomodoro-target="cancelButton"` を付ける
  - `shared.buttons.cancel`（= 「キャンセル」）は `config/locales/views/ja.yml` に既存
  - 未スタート時は `beforeunload` リスナーも活動ロックも未取得なので、Turbo Drive の素の遷移で安全に抜けられる
- 「終了する」に `hidden` クラスと `data-pomodoro-target="finishButton"` を付ける
  - 初期状態はマークアップを正とする（`connect()` で消すとチラつく）

休憩画面（`_break_screen.html.erb`）の「終了する」は、休憩に入る時点で必ずスタート済みのため表示制御は不要。確認ダイアログは `finish()` 側に入るので自動的に効く。

## JS: `app/javascript/controllers/pomodoro_controller.js`

`static targets` に `cancelButton` / `finishButton` を追加する。

### 表示の入れ替え

`start()` の「初回のみ」ブロック内、`this.firstStartedAt = new Date()` の直後に置く。

```js
this.finishButtonTarget.classList.remove("hidden")
this.cancelButtonTarget.classList.add("hidden")
```

浄化タイマーのガード（`isPurificationCounting()`）に引っかかるとその手前で `location.replace` するため、**ガードを通過した後にだけ入れ替わる**位置であることが要点。ブロックの外に出すと、計測を開始していないのにキャンセルだけが消える。

### 確認ダイアログと `finish()` の分割

`finish()` には現在 3 つの呼び出し元がある。

| 呼び出し元 | ファイル | 確認 |
|---|---|---|
| 作業画面「終了する」 | `_timer_buttons.html.erb` | **あり** |
| 休憩画面「終了する」 | `_break_screen.html.erb` | **あり** |
| モチベーション画面「それでいいもん」 | `_motivation_screen.html.erb` | **なし** |

「それでいいもん」に確認を出さないのは、その画面自体が「本当にそれでいいですか？」と問い、ボタンがその答えになっているためである。ここに `confirm()` を重ねると問いが 3 段になる。

入口を 2 つに分け、保存処理は 1 箇所に集約する。

```js
// 「終了する」（作業画面・休憩画面）から呼ばれる。確認を取ってから終了する。
finish() {
  // 確認ダイアログで迷っていた時間を活動時間に加算しないため、押した瞬間を先に取る
  const lastEndedAt = new Date()

  if (!window.confirm("終了してよろしいでしょうか？")) return

  this.completeSession(lastEndedAt)
}

// モチベーション画面「それでいいもん」から呼ばれる。画面自体が
// 「本当にそれでいいですか？」と確認を兼ねているので、二重に確認しない。
giveUp() {
  this.completeSession(new Date())
}

// 計測を止めて活動記録フォームへ遷移する。finish() / giveUp() の共通処理。
completeSession(lastEndedAt) {
  if (!this.firstStartedAt) {
    alert("スタートボタンを押してください")
    return
  }
  // 以降は現行 finish() の本体（clearInterval → removeBeforeUnloadListener → 遷移）
}
```

`_motivation_screen.html.erb` の「それでいいもん」の `data-action` を `click->pomodoro#finish` から `click->pomodoro#giveUp` に変更する。

**確認は副作用より前に通す。** 現在の実装は `clearInterval` と `removeBeforeUnloadListener()` を先に実行している。確認をその後ろに置くと、**キャンセルした時にタイマーが止まったまま画面だけ残る**という壊れ方をする。

`lastEndedAt` は確認ダイアログの前に取る。迷っていた時間を活動時間に加算しないためである。ネイティブ `confirm()` は JS の実行を止めるが、このコントローラの残り時間は `endedAt` からの差分計算なので、ダイアログを閉じた後も表示はズレない。

### なぜネイティブ `confirm()` か

- 「終了する」は `<button>` の Stimulus アクション（`click->pomodoro#finish`）であり、リンク／フォーム送信ではないため Rails の `data-turbo-confirm` は発火しない
- 同コントローラは既に `alert()` を使っており、System Spec も `accept_confirm` / `dismiss_confirm` でそのまま検証できる
- 自前モーダルにすると、計測中の画面に非同期の状態がもう 1 つ増える

### `alert("スタートボタンを押してください")` は残す

未スタート時に「終了する」は存在しなくなるが、**モチベーション画面はスタート前でも開ける**（`_motivation_button.html.erb` は作業画面に常時表示されている）。したがって未スタートのまま「それでいいもん」へ到達でき、このガードは依然として必要である。外すと `saveActivityRecord()` が `lastEndedAt - null` を計算して `NaN` になる。

ガードは `completeSession()` の先頭に置き、両方の入口を一度に守る。

### 触らないもの

無操作 20 分の自動保存（`saveActivityRecordWithInactivityTimeout`）は `finish()` を経由しないので確認は挟まらない。自動処理に確認は不要であり、意図どおりである。

## 「使い方」ページ: `app/views/static_pages/how_to_use/_step3.html.erb`

step2 の `※ 誤ってこの画面に来た／光の時間での行動が違う場合は、ブラウザの戻るボタンで戻りましょう。` を、キャンセルボタンを案内する文言に差し替える。この導線をキャンセルボタンが担うようになるためである。

## テスト

`spec/system/activity_records_spec.rb`

| 行 | 対応 |
|---|---|
| :54 「スタートボタンと終了するボタンが表示されること」 | 「スタート」＋「キャンセル」が表示され、「終了する」は非表示、へ書き換え |
| :61 「スタートせずに『終了する』をクリックするとアラートが表示されること」 | 「終了する」は存在しなくなるので、経路を**モチベーション画面の「それでいいもん」**に付け替える（アラート自体は残るため、テストも残す） |
| :204, :227 スタート後に終了 → 新規作成画面へ遷移 | `accept_confirm { click_on "終了する" }` に変更 |
| :244 「それでいいもん」→ 新規作成画面へ遷移 | 変更不要（確認を出さないため） |
| :140 休憩画面のボタン表示確認 | 変更不要 |

`spec/system/timer_exclusion_spec.rb:144` の作業画面「終了する」クリックも `accept_confirm` が必要。

**新規追加 2 件:**

1. 「キャンセルをクリックするとマイページへ戻ること」
2. 「確認ダイアログをキャンセルするとタイマーが継続すること」 — `dismiss_confirm` の後も `new_activity_record_path` へ遷移せず、`startButton` が hidden のままであることを確認する。「確認を副作用より前に通す」を守るためのテストなので必須。

## スコープ外

`app/assets/images/how_to_use/pomodoro_before_start.png` は「終了する」が写っているため実画面とズレる。差し替えには手動キャプチャが必要なので本件では対応しない（issue #263 に記載済み）。
