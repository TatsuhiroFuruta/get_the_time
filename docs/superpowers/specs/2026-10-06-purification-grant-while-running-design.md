# 実行中の浄化タイマーに付与された時間が stop! で消える不具合の修正 設計書

関連 issue: [#282](https://github.com/TatsuhiroFuruta/get_the_time/issues/282)

> この設計書は、チャットで承認された設計を実装後に書き起こしたものです（本来は実装前に作成すべきでした）。設計の内容は承認時から変えていません。

## 目的

浄化タイマーが `running` の間に付与された時間が、その後の `stop!` / `finish!` で失われないようにする。

## 現状の問題

### `running` 中のカラムの役割

| カラム | 意味 |
|---|---|
| `started_at` | スタートした時刻 |
| `total_time` | スタート時点の残り秒数のスナップショット（`start!` が `remaining_time` をコピーする） |
| `remaining_time` | `running` 中は参照されない値。止めたときに書き戻される |

`running` 中の「いまの残り」と「期限」は `total_time` から計算される。

- サーバーの残り時間（`stop!`）：`total_time - 経過秒`
- サーバーの期限（`counting?`）：`started_at + total_time`
- 画面表示（`purification_timer_controller.js`）：`remaining_time - 経過秒`

`start!` した瞬間は `remaining_time == total_time` なので、サーバーと画面の計算が一致する。

### 付与が `remaining_time` にしか入らない

`PurificationTimeGranter` は `remaining_time += minutes * 60` だけを行い、`total_time` には触れない。そのため `running` 中に付与されると、次の `stop!` が `total_time` から残りを計算し直し、付与分が消える。

### 付与が着弾する経路

**(1) 期限切れのまま `running` で残っているタイマー（主な経路）**

1. 浄化タイマーの起動中に画面を閉じる（`stop!` が呼ばれず `running` のまま残る）
2. 期限が過ぎたあとにポモドーロを回して、活動記録を保存する（ここで付与される）
3. 浄化タイマー画面を開く → JS の残りが 0 以下なのでチャイムが鳴り、鳴り終わると `stop()` が自動で呼ばれる（自動再生がブロックされた場合は終了ボタンを押したとき）→ `finish!` で 0 になる

手順 2 でポモドーロを始められるのは、`counting?` が期限切れの `running` に対して false を返すため。これは #265 の永久ロック対策で、意図的な設計。

```
10:00  start!   started_at 10:00 / total_time 600 / remaining_time 600
10:10  期限切れ。画面は閉じたまま（status は running）
11:00  活動記録を保存 → 10 分付与 → remaining_time 1200 / total_time 600
11:05  stop!    残り = 600 - 3900 < 0 → finish! → remaining_time 0（付与分が消える）
```

**(2) 計測中のタイマー（まれな経路）**

同じブラウザ内では、活動記録フォームが localStorage のリース（`activity_lock.js`）を持っている。そのため浄化タイマー画面は開けず、スタートもできない。リースが効かないのは、別ブラウザや別端末からの操作、バックグラウンドで止められたタブでのリース失効、Storage が使えない環境だけ。

```
10:00  start!   total_time 600 / remaining_time 600
10:04  付与 5 分 → remaining_time 900 / total_time 600
10:06  stop!    残り = 600 - 360 = 240（本来は 540）
```

## 設計

### `PurificationTime#add_time(seconds)` を追加する

付与時の状態で扱いを分ける。`running` かどうかの判定をモデルに閉じ込め、Granter が状態遷移の内部事情を知らずに済むようにする。

| 付与時の状態 | 処理 |
|---|---|
| `running` かつ `counting?`（期限前） | `remaining_time` に加算し、`total_time` を `remaining_time + 付与秒` に揃える。期限が後ろへずれ、タイマーが延びる |
| `running` だが期限切れ（`counting?` が false） | 先に `finish!` と同じ属性（`idle`・残り 0・`total_time` 0・`started_at` / `paused_at` nil）に精算してから、`remaining_time` に加算する |
| `idle` / `paused` | 従来どおり `remaining_time` に加算するだけ |

- **保存はしない。** Granter が払い出し台帳（`granted_blocks_date` / `granted_blocks_count`）と一緒に、`with_lock` 内で 1 回だけ `save!` する流れを保つ。保存を連想させないよう、メソッド名に `!` は付けない。
- `finish!`・`reset!`・精算で同じ属性を使うので、private の `finished_attributes` に切り出して共有する。
- 計測中の分岐で `total_time` に同じ秒数を足すのではなく `remaining_time` に揃えるのは、修正前の付与で `remaining_time > total_time` になったデータがありうるため。修正前は `remaining_time` にだけ付与が入っていたので、`remaining_time` の方が本来の残りになる（コードレビューで指摘を受けて追加）。
- 精算でも払い出し台帳には触れない（`reset!` / `finish!` と同じ不変条件）。

### `PurificationTimeGranter` の変更

`purification_time.remaining_time += minutes * 60` を `purification_time.add_time(minutes * 60)` に置き換える。それ以外は変えない。

### 決定事項と理由

- **期限切れのタイマーは延ばさずに精算する。** issue の原案「`running` なら `total_time` にも足す」だけでは、経路 (1) で延ばしても期限がまだ過去にあり、`stop!` で結局 0 になる。
- **精算後は `idle` にする**（その場で付与分の計測を再開しない）。ユーザーが画面を見ていないところでタイマーが減り始めるのを避けるため。`idle` なので `counting?` は false のままで、#265 の永久ロック対策も壊さない。
- **計測中は `remaining_time == total_time` を保つ。** 画面表示（`remaining_time` 基準）とサーバー（`total_time` 基準）の残りが一致する。

## 範囲外

- `ActivityRecordsController#create` に浄化タイマーのサーバー側ガードを足すこと。経路 (2) はまれな経路で、本修正によって着弾しても時間は失われなくなる。必要になったら別 issue で扱う。
- フロントエンド（`purification_timer_controller.js`）の変更。計測中は `remaining_time == total_time` が保たれるので、JS はそのままでよい。
  - ただし、計測中に付与される前から浄化タイマー画面を開いていた別の端末やタブでは、JS が古い残り時間のまま動くため、旧い期限でチャイムが鳴って `stop()` を呼ぶ。サーバー側には残りがあるので `pause!` になるだけで、時間は失われない（経路 (2) 自体がまれなので許容する）。
- 浄化タイマーの `start` / `stop` / `reset` と付与の直列化。これらはロックを取らずに更新するため、付与と同時に走ると片方の更新が上書きされうる。修正前から存在する問題で、#297 で扱う。

## テスト

### `spec/models/purification_time_spec.rb`（`#add_time`）

- `idle` / `paused` への付与は `remaining_time` に加算されるだけで、状態は変わらない
- 保存しない（`reload` すると元の値）
- 計測中に付与すると、`stop!` 後の残りに付与分が反映される
- 計測中に付与すると、`counting?` の期限が付与分だけ延びる
- 計測中の付与後も `remaining_time == total_time`
- 期限切れの `running` に付与すると、`idle` に精算されて残り＝付与分になり、`counting?` は false
- ちょうど期限の瞬間の付与は精算側に倒れる
- `running` だが `started_at` が nil の不正データでも例外を出さず、精算される
- `paused` 中に付与 → 再開 → 停止しても付与分が残る

### `spec/services/purification_time_granter_spec.rb`（running のとき）

- 経路 (2)：計測中に付与された分が `stop!` 後も残る（修正前は 840 秒になるべきところ 240 秒）
- 経路 (1)：期限切れのタイマーに付与された分が `stop!` 後も残る（修正前は 600 秒になるべきところ 0 秒）
- 期限切れのタイマーに付与しても払い出し台帳が更新され、同じブロックを再付与しない
- 計測中に付与した直後も `remaining_time == total_time` が保存後に保たれる

## 完了条件

- `running` 中に付与された時間が、その後の `stop!` / `finish!` で失われない
- 計測中に付与すると `counting?` の期限も延びる
- `idle` / `paused` 中の付与の挙動は変わらない
- 期限切れのまま `running` で残ったタイマーがポモドーロをブロックしない性質は維持される（#265）
- `docker compose exec web bundle exec rspec` が green
- `docker compose exec web bin/rubocop` が clean
