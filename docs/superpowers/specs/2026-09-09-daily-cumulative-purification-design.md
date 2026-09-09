# 浄化タイマーの付与を1日の累計時間ベースに変更する 設計書

関連 issue: [#251](https://github.com/TatsuhiroFuruta/get_the_time/issues/251)

## 目的

浄化タイマーの付与単位を「1 セッションの活動時間」から「**1 日の累計活動時間**」に変える。30 分に満たない活動が切り捨てられる現状をやめ、短いセッションの積み重ねが報われるようにする。

## 現状の問題

`ActivityRecord.calculate_purification_time(total_duration)` は 1 セッションの `total_duration` だけを見て `floor(total_duration / 30)` ブロック分を付与する。セッションをまたいだ持ち越しがないため、25 分のセッションを 2 回こなしても付与は 0 になる。

```
25分 → floor(25/30) = 0 ブロック
25分 → floor(25/30) = 0 ブロック
合計 50 分働いて付与 0
```

ポモドーロの標準設定は活動 25 分（`pomodoro_settings.work_duration` のデフォルト）なので、**1 セッションで終える使い方が構造的に報われない**。

## 付与ルール（変更後）

その日の光の時間の累計が 30 分たまるごとに 1 ブロック付与する。1 ブロックにつき既存の重み付き抽選（8 分 60% / 10 分 30% / 13 分 9% / 15 分 1%）を 1 回引き、合計を浄化タイマーに加算する。

活動記録を保存した時点で、**その保存によって新たに越えたブロック数**だけを付与する。

```
新規ブロック数 = floor(保存後の当日累計 / 30) − floor(保存前の当日累計 / 30)
```

| 保存する活動 | 保存前の累計 | 保存後の累計 | 付与済みブロック | 今回の付与 | 余り |
| --- | --- | --- | --- | --- | --- |
| 25 分 | 0 | 25 | 0 → 0 | 0 ブロック | 25 分 |
| 25 分 | 25 | 50 | 0 → 1 | **1 ブロック** | 20 分 |
| 90 分 | 50 | 140 | 1 → 4 | **3 ブロック** | 20 分 |
| 125 分 | 140 | 265 | 4 → 8 | **4 ブロック** | 25 分 |

累計・余りともに 0 時（JST）にリセットする。余りは翌日へ繰り越さない。

## なぜカラムを追加しないのか

「余りを繰り越さない」と決めたことで、**その日の状態は累計 1 つで完全に決まる**。付与済みブロック数も余りも、累計から割り算と剰余で導出できる。

```
累計 265 分（4 時間 25 分）
  付与済みブロック = 265 / 30 = 8 ブロック（= 240 分ぶんを消化済み）
  余り            = 265 % 30 = 25 分
```

付与履歴を保存する必要がないので、マイグレーションもカラム追加も不要である。`before` を「前回までに何ブロック付与したかの記録」ではなく**累計からの再計算**として求めるのがこの設計の要点で、状態を持たないぶん日付リセットの同期漏れも起こりえない。

導出できるのはブロック数であって、実際に付与した分数（乱数で決まる 8/10/13/15 分）ではない。ただし付与済み分数は `purification_times.remaining_time` に加算済みで後から再現する必要がなく、付与判定にはブロック数しか使わないため問題にならない。

## 基準日を `ended_at` に変える

`ActivityRecord` の「その活動がどの日のものか」の判定を、`created_at`（記録の送信時刻）から **`ended_at`（活動の終了時刻）** に変更する。

`created_at` は活動記録フォームを送信した時刻なので、実際に活動した時間帯とずれる。23:00〜23:50 の活動を 00:05 に送信すると翌日扱いになり、**0 時をまたいだかどうかを正しく判定できない**。

`ended_at` はポモドーロの `pomodoro_controller.js:350` で最後の活動時刻が入るため、実態に沿う。

### 揃える範囲

| 対象 | 現状 | 変更後 |
| --- | --- | --- |
| 浄化タイマー付与の当日累計 | （セッション単位のため累計なし） | `ended_at` 基準 |
| マイページ「今日の光の時間」 | `created_at` 基準 | `ended_at` 基準 |
| マイステータスの日次グラフ | `created_at` 基準 | `ended_at` 基準 |
| `within_last_days`（直近 N 日の窓） | `created_at` 基準 | `ended_at` 基準 |

マイページとグラフまで揃えるのは、**表示と付与で基準がずれると付与タイミングが説明不能になる**ためである。「今日の光の時間 50 分」と表示されているのに付与されない、あるいはその逆が起きる。

`within_last_days` は直近 30 日の窓を切るだけで averages の値にはほとんど影響しないが、`daily_series` が同じ窓を使っているため、日付バケットだけ `ended_at`・窓だけ `created_at` という食い違いを残さない。**日付の定義は 1 箇所に集約する。**

### `COALESCE` で包む理由

`ended_at` は `db/schema.rb:21` で NOT NULL 制約がなく、モデルにも presence バリデーションがない。素の `ended_at` で絞ると、NULL のレコードは `WHERE` の判定が unknown になり**どの日の集計にも入らなくなる**。エラーではなく「黙って消える」壊れ方をするため気づきにくい。

```sql
COALESCE(activity_records.ended_at, activity_records.created_at)
```

`created_at` は NOT NULL なので、この式は絶対に NULL を返さない。

通常フローでは NULL にならない（ポモドーロ経由も `db/seeds.rb:38` も必ず値を入れる）ため、これは現時点では発動しない防御である。それでも残すのは、上記のとおり失敗の症状が静かだからである。

`ended_at || created_at` のような Ruby 側の分岐は使えない。集計は `SUM` / `GROUP BY` で SQL 側に閉じる必要があり、レコードを 1 件ずつ読み込むわけにはいかないためである。

## 0 時またぎの扱い

セッションは終了した日に丸ごと計上されるため、0 時をまたぐセッションは自動的に「新しい日の最初の活動」になる。前日の累計・余りはリセット済みなので、**そのセッション単体で `floor(セッション時間 / 30)` ブロックが必ず付与される**。

```
前日: 09:00〜23:00 で累計 25 分 → 付与 0（余り 25 分）
--- 0 時 --- 累計 0 / 余り 0 にリセット
23:50〜00:40 (50 分) → 当日累計 50 分 → 1 ブロック付与（余り 20 分）
01:00〜01:10 (10 分) → 当日累計 60 分 → 1 ブロック付与（余り 0 分）
```

**またぎ専用の分岐は実装に登場しない。** 基準日を `ended_at` にした結果として要件が満たされる。

### 検討して採らなかった案

**0 時で分割して両日に配分する案。** `total_duration` は壁時計の経過分数（`pomodoro_controller.js:344` — `floor((lastEndedAt - firstStartedAt) / 60000)`）なので分割自体は可能だが、採らない。

- 1 レコードが 2 日に寄与するため `SUM(total_duration)` が使えなくなり、日付バケットの集計を専用ロジックに置き換える必要が出る。マイページとグラフも同じロジックに揃えないと表示と付与がずれる
- 30 分ちょうどのまたぎセッション（15 分 + 15 分）で付与 0 になり、**要件そのものを満たさない**

**またぎのときだけ前日の余りを引き継ぐ案。** 繰り越しカラム 2 本で実装できるが、採らない。日をまたいだ瞬間に余りが消えるのは**またぎセッションの有無に関わらず毎晩起きる**ことであり、ここで後者だけ救済すると、同じ「前日の 25 分」が寝たか活動を続けたかで扱いが変わる。ユーザーに説明できないルールになる。

「余りは毎晩 0 時に必ず消える」という一貫したルール 1 本で通す。

## 変更しないもの

- **`PURIFICATION_TIME_TABLE`** — 分数も重みも据え置き
- **1 ブロック = 30 分** — ブロックの粒度は変えない
- **付与のタイミング** — 従来どおり活動記録の保存時。ポモドーロ終了時ではない
- **活動記録保存後のフラッシュ**（`app/controllers/activity_records_controller.rb:24-30`）— 付与 0 のときは従来どおり無言。進捗はマイページで確認する形にする
- **`ActivityRecordForm` のトランザクション構成** — `ActivityRecord` 作成 → `LightTime` / `DarkTime` 更新 → 浄化タイマー付与、の流れは維持
- **活動記録を削除しても浄化タイマーは返却しない** — 現行仕様どおり。乱数で付与した分数をレコードに保存していないため、正確な返却はそもそもできない

## 実装

### `app/models/activity_record.rb`

日付の定義を定数 1 つに集約し、それを使う 3 つのスコープを揃える。

```ruby
# 「その活動がどの日のものか」を表す式。活動の終了時刻（ended_at）を正とする。
# created_at は記録の送信時刻なので、0 時をまたぐ活動や後日の登録で実態とずれる。
# ended_at が未設定のレコードだけ created_at にフォールバックする。created_at は
# NOT NULL なので、この式が NULL を返して集計から黙って漏れることはない。
ACTIVITY_AT = "COALESCE(activity_records.ended_at, activity_records.created_at)".freeze

scope :activity_on, ->(date) {
  range = date.all_day
  where("#{ACTIVITY_AT} BETWEEN ? AND ?", range.begin, range.end)
}

scope :today, -> { activity_on(Date.current) }

scope :within_last_days, ->(days) {
  where("#{ACTIVITY_AT} >= ?", days.days.ago.beginning_of_day)
}
```

`total_light_time_today(user)` は `total_light_time_on(user, date)` に一般化する。付与ロジックが「そのレコードの日」の累計を必要とし、必ずしも今日とは限らない（`travel_to` を使うテスト、日をまたいだ直後の保存）ためである。`total_light_time_today` は `Date.current` を渡す薄いラッパとして残す。

`daily_series` の日付バケットも同じ式にする。

```ruby
bucket = Arel.sql("DATE((#{ACTIVITY_AT} AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Tokyo')")
```

付与計算は純粋関数に分解する。乱数を含む部分と含まない部分を分けることで、ブロック数の計算をスタブなしで検証できる。

```ruby
PURIFICATION_BLOCK_MINUTES = 30

# 累計分数から消化済みブロック数を求める
def self.purification_blocks(minutes)
  [ minutes.to_i, 0 ].max / PURIFICATION_BLOCK_MINUTES
end

# blocks 回の抽選を引いた合計分数
def self.sample_purification_minutes_for(blocks)
  return 0 if blocks <= 0

  blocks.times.sum { sample_purification_minutes }
end

# 次の付与までの残り分数（マイページ表示用）
def self.minutes_until_next_purification(total_minutes)
  PURIFICATION_BLOCK_MINUTES - [ total_minutes.to_i, 0 ].max % PURIFICATION_BLOCK_MINUTES
end
```

`purification_blocks` の `[minutes, 0].max` は負値ガードである。Ruby の整数除算は負の無限大方向に丸めるため（`-5 / 30 == -1`）、万一 `保存前の累計` が負になると `before` が `-1` になってブロック数が水増しされる。

既存の `self.calculate_purification_time(total_duration)` は呼び出し元がなくなるため削除する。

### `app/services/purification_time_granter.rb`

セッションの分数だけでは当日累計を引けないため、`call(total_duration)` を `call(activity_record)` に変える。

```ruby
def call(activity_record)
  @user.with_lock do
    blocks = newly_earned_blocks(activity_record)
    next 0 if blocks <= 0

    minutes = ActivityRecord.sample_purification_minutes_for(blocks)
    purification_time = @user.purification_time || @user.build_purification_time
    purification_time.remaining_time += minutes * 60
    purification_time.save!
    minutes
  end
end

private

# 保存後の当日累計と保存前の当日累計の差分ブロック数
def newly_earned_blocks(activity_record)
  total_after  = ActivityRecord.total_light_time_on(@user, activity_day(activity_record))
  total_before = total_after - activity_record.total_duration.to_i

  ActivityRecord.purification_blocks(total_after) - ActivityRecord.purification_blocks(total_before)
end

def activity_day(activity_record)
  (activity_record.ended_at || activity_record.created_at).in_time_zone.to_date
end
```

`total_after` は `create!` の後に取るため今回のレコードを含む。「保存前の累計」は自分の分を引いて求める。

**当日累計の読み取りからタイマー加算までを `with_lock` の中に入れる。** 現状は付与分数の計算がロックの外にあるが、セッション単位の計算では他レコードを参照しないため問題にならなかった。累計ベースにすると、2 つの記録が同時に保存されたときに**両方が同じ累計を読んで同じブロックを二重付与しうる**。読み取りをロック内に移すことで直列化する。

`with_lock` は `transaction` 経由でブロックの戻り値を返すので、`next 0` / `minutes` がそのまま `call` の戻り値になる。付与した実分数を返す既存の契約（`ActivityRecordForm#granted_purification_minutes` 経由でフラッシュに表示）は維持する。

### `app/forms/activity_record_form.rb`

`create!` の戻り値を受け取って Granter に渡す。トランザクション構成は変えない。

```ruby
activity_record = user.activity_records.create!(...)
...
@granted_purification_minutes = PurificationTimeGranter.new(user).call(activity_record)
```

### マイページの進捗表示

累計制にすると「25 分やったのに何ももらえなかった」という状態が生まれるため、次の付与までの残り分数を常時表示する。これがないとユーザーから見て付与タイミングが不可解になる。

`app/controllers/mypages_controller.rb`

```ruby
@today_light_time = ActivityRecord.total_light_time_today(current_user)
@minutes_to_next_purification = ActivityRecord.minutes_until_next_purification(@today_light_time)
```

`app/views/mypages/_pomodoro_start.html.erb` の「今日の光の時間」の直下に追加する。

```
今日の光の時間
    50 分
次の浄化タイマーまで あと 10 分
```

累計 0 分のときも 30 分と表示される（`30 - 0 % 30 = 30`）。0 と表示するより「これから 30 分で 1 つ目がもらえる」と読める方が目的に合う。

### ドキュメント

`README.md:117` の「活動記録を提出すると光の時間 30 分につき 10 分『浄化タイマー』が付与される」を累計ベースの記述に更新する。

`CLAUDE.md` の「活動記録のフロー」節は `ActivityRecord.calculate_purification_time` と `PurificationTimeGranter.new(user).call(total_duration)` を名指しで説明している。**両方とも本設計で変わるため、同時に更新する。**

## テスト

### `spec/services/purification_time_granter_spec.rb`

全面改訂する。`call` の引数が分数から `ActivityRecord` に変わるため、既存の example はそのまま使えない。ブロック数を検証する example では `ActivityRecord.sample_purification_minutes` をスタブして 1 ブロック 10 分に固定する（現行 spec と同じ手法）。

- 25 分 1 本 → 付与 0
- 25 分 + 25 分 → 2 回目の保存で 1 ブロック付与
- 90 分 1 本（累計 50 → 140）→ 3 ブロック付与
- 日付が変わると累計がリセットされる（`travel_to`）
- 0 時をまたぐ 30 分セッション（`started_at` 23:45 / `ended_at` 00:15）は、前日に 25 分の余りがあっても当日扱いになり 1 ブロック付与（前日の余りは失効する）
- `ended_at` が NULL のレコードは `created_at` にフォールバックする
- `PurificationTime` が未作成のときは新規作成される（既存 example の意図を維持）

### `spec/models/activity_record_spec.rb`

`calculate_purification_time` の `describe` を削除し、`purification_blocks` / `sample_purification_minutes_for` / `minutes_until_next_purification` の `describe` に置き換える。前 2 つは既存 example の意図（境界値 29/30/59/60、呼び出し回数）を引き継ぐ。

**基準日の変更により、`update_column(:created_at, ...)` で日付を操作している既存 example が 7 箇所落ちる。** ファクトリが `ended_at { Time.current }` を設定しているため、`created_at` だけ過去に倒しても `COALESCE` は `ended_at`（今日）を拾うためである。

| 行 | describe | 対応 |
| --- | --- | --- |
| 280, 328, 369 | `evaluation_averages` / `fatigue_average` / `desired_self_percentage_average` の「30 日より古い記録」 | `ended_at` も 31 日前に倒す |
| 423 | `daily_series` の JST 日跨ぎ | `ended_at` を JST 5/28 0:30 に |
| 436, 438 | `daily_series` の複数日 | `ended_at` を各日付に |
| 450 | `daily_series` の期間外 | `ended_at` も 31 日前に |

これは仕様変更の副作用として避けられない修正であり、テストが基準日の変更を正しく検出している証拠でもある。

### `spec/forms/activity_record_form_spec.rb`

`granted_purification_minutes` が累計ベースになることを検証する。フォーム経由で 25 分を 2 回保存し、2 回目で付与が発生することを見る。

### `spec/system/purification_times_spec.rb`

マイページに「次の浄化タイマーまで あと○分」が表示されることを検証する。

**新規に `spec/system/mypages_spec.rb` は作らない。** マイページ用の system spec / request spec は存在せず、`visit mypage_path` を持つ既存ファイルはこの `purification_times_spec.rb` である。表示内容も浄化タイマーに関するものなので、ここが適切な置き場所になる。

## 移行

**データ移行は不要。** 旧仕様の付与済み合計は `Σ floor(セッション / 30)`、新仕様は `floor(Σ / 30)` で、常に `旧 ≤ 新` が成り立つ。

リリース当日にすでに記録があるユーザーは、旧仕様で取りこぼしていた端数が回収されて少し多めに付与されることがあるが、二重付与にはならない。翌日以降は完全に新仕様で動く。

## 既知の制約

当日累計をレコードから導出するため、**活動記録を削除すると付与済みブロック数の導出値が下がり、同じ活動時間で再度ブロックを獲得できる**。

```
30 分の記録を保存 → 累計 30 → 1 ブロック付与（浄化タイマー +10 分）
その記録を削除     → 累計 0（付与済みブロックの導出値も 0 に戻る）
30 分の記録を保存 → 累計 30 → もう 1 ブロック付与（+10 分）
```

付与した事実（`remaining_time`）は残るのに、付与済みの記録（累計）だけが消えることによる食い違いである。

塞ぐには `purification_times` に「当日の付与済みブロック数」と「その日付」を持たせる必要があるが、自分の活動記録（「本来の自分」の推移・レーダーチャート・日次グラフの元データ）を消してまで 8〜15 分のタイマーを稼ぐ動機が薄いため、今回は対策しない。ランキングなど競争要素を入れる際は再検討する。

## スコープ外

- **抽選テーブルの調整** — 累計制で付与機会が増えるため体感の獲得量は上がるが、まずは現行テーブルのまま様子を見る
- **活動記録保存後のフラッシュへの進捗表示** — マイページの常時表示で足りるか確認してから判断する
- **活動記録の削除による二度取りの防止** — 上記「既知の制約」のとおり

## 実装時に判断する点

`ACTIVITY_AT` を `where` に文字列補間する形が Brakeman の SQL injection 警告に触れる可能性がある。定数に代入されたリテラルなので実際の危険はないが、CI の `scan_ruby` ジョブが落ちる場合は定数化をやめ、各スコープに SQL リテラルを直書きする方針に切り替える（DRY より CI が通ることを優先）。
