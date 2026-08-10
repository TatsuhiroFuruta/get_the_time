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

### 確認ダイアログ

`finish()` の先頭に置く。順序が重要。

```js
finish() {
  const lastEndedAt = new Date()          // 押した瞬間を終了時刻とする

  if (!window.confirm("終了してよろしいでしょうか？")) return   // ← clearInterval より前

  if (this.timerInterval) { ... }         // 以降は現状のまま
```

現在の実装は `clearInterval` と `removeBeforeUnloadListener()` を先に実行している。確認をその後ろに置くと、**キャンセルした時にタイマーが止まったまま画面だけ残る**という壊れ方をする。確認は必ず副作用より前に通す。

`lastEndedAt` は確認ダイアログの前に取る。迷っていた時間を活動時間に加算しないためである。ネイティブ `confirm()` は JS の実行を止めるが、このコントローラの残り時間は `endedAt` からの差分計算なので、ダイアログを閉じた後も表示はズレない。

### なぜネイティブ `confirm()` か

- 「終了する」は `<button>` の Stimulus アクション（`click->pomodoro#finish`）であり、リンク／フォーム送信ではないため Rails の `data-turbo-confirm` は発火しない
- 同コントローラは既に `alert()` を使っており、System Spec も `accept_confirm` / `dismiss_confirm` でそのまま検証できる
- 自前モーダルにすると、計測中の画面に非同期の状態がもう 1 つ増える

### 削除するもの

`alert("スタートボタンを押してください")` を削除する。未スタート時に「終了する」が存在しなくなり、このパスが到達不能になるためである。到達不能なコードと、それを守るテストの両方を残さない。

### 触らないもの

無操作 20 分の自動保存（`saveActivityRecordWithInactivityTimeout`）は `finish()` を経由しないので確認は挟まらない。自動処理に確認は不要であり、意図どおりである。

## 「使い方」ページ: `app/views/static_pages/how_to_use/_step3.html.erb`

step2 の `※ 誤ってこの画面に来た／光の時間での行動が違う場合は、ブラウザの戻るボタンで戻りましょう。` を、キャンセルボタンを案内する文言に差し替える。この導線をキャンセルボタンが担うようになるためである。

## テスト

`spec/system/activity_records_spec.rb`

| 行 | 対応 |
|---|---|
| :54 「スタートボタンと終了するボタンが表示されること」 | 「スタート」＋「キャンセル」が表示され、「終了する」は非表示、へ書き換え |
| :61 「スタートせずに『終了する』をクリックするとアラートが表示されること」 | 削除（到達不能）。代わりに「キャンセルでマイページへ戻ること」を追加 |
| :204, :227 スタート後に終了 → 新規作成画面へ遷移 | `accept_confirm { click_on "終了する" }` に変更 |
| :140 休憩画面のボタン表示確認 | 変更不要 |

`spec/system/timer_exclusion_spec.rb:144` の作業画面「終了する」クリックも `accept_confirm` が必要。

**新規追加:** 「確認ダイアログをキャンセルするとタイマーが継続すること」。`dismiss_confirm` の後も `new_activity_record_path` へ遷移せず、`startButton` が hidden のままであることを確認する。上記「確認を副作用より前に通す」を守るためのテストなので必須。

## スコープ外

`app/assets/images/how_to_use/pomodoro_before_start.png` は「終了する」が写っているため実画面とズレる。差し替えには手動キャプチャが必要なので本件では対応しない（issue #263 に記載済み）。
