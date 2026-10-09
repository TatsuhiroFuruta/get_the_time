# 浄化タイマーの報酬ルールと付与を `PurificationReward` に統合する 設計書

関連 issue: [#284](https://github.com/TatsuhiroFuruta/get_the_time/issues/284)

## 目的

浄化タイマーの付与にかかわるコードを 1 か所にまとめる。現在は次の 2 か所に分かれている。

| 場所 | 中身 |
| --- | --- |
| `app/models/activity_record.rb:90-133` | 付与ルール（ブロックの粒度・抽選テーブル・ブロック数の計算・次の付与までの分数） |
| `app/services/purification_time_granter.rb` | 付与の実行（`with_lock` の中で累計と台帳を読み、差分を `PurificationTime` に加算する） |

付与ルールは `ActivityRecord` のインスタンスを一切参照しない純粋関数と定数で、活動記録の関心事ではない。これらを新しいモデル `PurificationReward` に移し、Granter の処理も同じクラスに統合する。

**挙動は一切変えない。** 付与される分数・ブロック数・マイページの表示分数は移設前と同じになる。

## 判断の経緯

issue #284 の当初の本文では「移設先は Granter ではない。純粋なルールだけを専用オブジェクトに切り出す」としていた。設計の議論でこれを見直し、Granter も統合することにした。

### Granter を統合する理由

Granter を別クラスにしておく価値として、次の 3 点を検討した。

| 観点 | 検討結果 |
| --- | --- |
| 純粋なルールに副作用が混ざる | Rails のモデルは、問い合わせと DB の変更を同じクラスに持つのが普通である。`PurificationTime` も `granted_blocks_for`（問い合わせ）と `add_time`（変更）を両方持っている。マイページが `minutes_until_next` を呼んでも何も書き換わらないので、実害はない |
| 付与ロジックを単独でテストしたい | これは付与ロジックの価値で、Granter というクラスの価値ではない。統合先の spec に `describe ".grant!"` として移せば、そのまま残る |
| ルールと DB への反映を分けておける | 純粋な部分の呼び出し元が多い場合や、ルールを差し替える場合に効く。現在の呼び出し元は Granter とマイページの 2 か所だけである |

最後の 1 点だけが残る価値だが、それよりも「浄化タイマーの付与は `PurificationReward` を見れば全部わかる」という一貫性の方が大きいと判断した。

### サービスではなくモデルに置く理由

`app/services/` にある副作用のあるサービスは、4 つとも公開メソッドが `call` だけである。

| クラス | 公開メソッド |
| --- | --- |
| `GuestUserBuilder` | `call` |
| `GuestUserPurger` | `call` |
| `PurificationTimeGranter` | `call` |
| `RegretSummarizer` | `call` |

このプロジェクトでは、サービスは「入口が `call` ひとつの手続き」である。統合後の `PurificationReward` は、書き込み（`grant!`）、問い合わせ（`minutes_until_next`）、ルール（`blocks` など）と入口が複数あり、大半は問い合わせである。これは手続きではなく、「浄化タイマーの報酬」という概念がルールを持ち、自分を付与することもできる、という形で、モデルの典型にあたる。

サービスに置く場合の 2 案は、どちらも採らない。

- **`PurificationTimeGranter` にすべて入れる**: マイページが表示のために「付与する人」を呼ぶことになり、名前と使われ方が食い違う
- **`PurificationReward` を `app/services/` に置く**: `call` を持たない名詞のクラスがサービスに混ざり、「サービス = `call` ひとつの手続き」という今の読み方が崩れる

なお `app/services/guest_demo_data.rb` は副作用のない `module` で、上の読み方の例外にあたる。今回はこの前例には合わせない。

## 新しいクラス

`app/models/purification_reward.rb` を作る。テーブルを持たない PORO で、`ApplicationRecord` を継承しない。インスタンスは作らず、定数とクラスメソッドだけを持つ。Granter の状態は `@user` だけだったので、`grant!` も他と形を揃えてクラスメソッドにする。

```ruby
# 浄化タイマーの報酬（付与）のルールと、その実行をまとめたクラス。テーブルは持たない。
class PurificationReward
  BLOCK_MINUTES = 30
  TIME_TABLE = [ ... ].freeze

  def self.sample_minutes
  def self.blocks(minutes)
  def self.sample_minutes_for(blocks)
  def self.minutes_until_next(total_minutes, granted_blocks = 0)
  def self.grant!(user, activity_record)

  def self.unpaid_blocks(user, day, granted)
  private_class_method :unpaid_blocks
end
```

各メソッドの中身とコメントは移設前のまま写す。変わるのは次の 3 点だけである。

- 名前（下表）
- 定数・メソッドの参照先（`ActivityRecord.xxx` → `PurificationReward` 内の呼び出し）
- `grant!` と `unpaid_blocks` が `@user` ではなく引数の `user` を使う

`grant!` の `!` は「DB を書き換え、失敗すると `save!` が例外を投げる」ことを示す。`with_lock` の範囲、`next 0` での早期リターン、戻り値（付与した分数、付与がなければ 0）は現行の `call` と同じにする。

### 名前の対応

クラス名に「purification」が入るので、メソッド名から接頭辞を外す。

| 移設前 | 移設後 |
| --- | --- |
| `ActivityRecord::PURIFICATION_BLOCK_MINUTES` | `PurificationReward::BLOCK_MINUTES` |
| `ActivityRecord::PURIFICATION_TIME_TABLE` | `PurificationReward::TIME_TABLE` |
| `ActivityRecord.sample_purification_minutes` | `PurificationReward.sample_minutes` |
| `ActivityRecord.purification_blocks` | `PurificationReward.blocks` |
| `ActivityRecord.sample_purification_minutes_for` | `PurificationReward.sample_minutes_for` |
| `ActivityRecord.minutes_until_next_purification` | `PurificationReward.minutes_until_next` |
| `PurificationTimeGranter.new(user).call(record)` | `PurificationReward.grant!(user, record)` |
| `PurificationTimeGranter#unpaid_blocks`（private） | `PurificationReward.unpaid_blocks`（private_class_method） |

## 変更しないもの

- **`ActivityRecord::ACTIVITY_AT` / `activity_date` / `total_light_time_on` / `total_light_time_today`**: 「その活動がどの日のものか」と「その日の累計」の定義は活動記録の関心事で、日次グラフや直近 N 日の集計も同じ定義を使っている。`grant!` からは `ActivityRecord` のこれらを呼ぶ
- **`purification_times` の台帳（`granted_blocks_date` / `granted_blocks_count`）と `PurificationTime#add_time` / `granted_blocks_for`**: 状態は `PurificationTime` が持つ
- **`ActivityRecordForm` のトランザクションの範囲**: Form は引き続き、活動記録の作成・特徴量の更新・付与を 1 つのトランザクションでまとめる。呼び出し先が変わるだけである
- **`blocks` の古いコメント**: 「余りを翌日へ繰り越さない設計のため、付与済みブロック数は累計だけから導出できる」は、#251 で台帳を導入したため現状と合っていない。ただしこの PR は移動だけにするため、そのまま移し、別 issue で直す

## 変更ファイル

### コミット 1: 付与ルールの移設

| ファイル | 変更内容 |
| --- | --- |
| `app/models/purification_reward.rb` | 新規。定数 2 つとクラスメソッド 4 つを移設 |
| `app/models/activity_record.rb` | 上記の定数とメソッドを削除 |
| `app/services/purification_time_granter.rb` | `ActivityRecord.purification_blocks` / `sample_purification_minutes_for` の呼び出しを差し替え |
| `app/controllers/mypages_controller.rb` | `minutes_until_next_purification` の呼び出しを差し替え |
| `spec/models/purification_reward_spec.rb` | 新規。`activity_record_spec.rb` の該当 4 つの describe を移設 |
| `spec/models/activity_record_spec.rb` | 移設した describe を削除 |
| `spec/services/purification_time_granter_spec.rb` | スタブ先を差し替え（10・66 行目） |
| `spec/forms/activity_record_form_spec.rb` | スタブ先を差し替え（168 行目） |
| `spec/requests/activity_records_spec.rb` | スタブ先を差し替え（200・222 行目） |
| `spec/system/activity_records_spec.rb` | スタブ先を差し替え（458 行目） |
| `spec/services/guest_user_builder_spec.rb` | スタブ先を差し替え（85 行目） |
| `CLAUDE.md` | 「活動記録のフロー」節の付与ルールの段落を更新 |

スタブ先は `allow(ActivityRecord).to receive(:sample_purification_minutes)` から `allow(PurificationReward).to receive(:sample_minutes)` に変える。`sample_minutes_for` は内部で `sample_minutes` を呼ぶので、このスタブで抽選結果を固定できる。

### コミット 2: 付与の実行の移設

| ファイル | 変更内容 |
| --- | --- |
| `app/models/purification_reward.rb` | `grant!` と `unpaid_blocks` を追加（Granter の `call` と `unpaid_blocks` を移設） |
| `app/services/purification_time_granter.rb` | 削除 |
| `app/forms/activity_record_form.rb` | `PurificationTimeGranter.new(user).call(activity_record)` を `PurificationReward.grant!(user, activity_record)` に差し替え |
| `spec/models/purification_reward_spec.rb` | `purification_time_granter_spec.rb` の `describe "#call"` を `describe ".grant!"` として移設 |
| `spec/services/purification_time_granter_spec.rb` | 削除 |
| `spec/services/guest_user_builder_spec.rb` | `PurificationTimeGranter.new(user).call(record)` を差し替え（95 行目） |
| `app/models/purification_time.rb` | コメント中の `PurificationTimeGranter` を差し替え（51 行目） |
| `app/services/guest_demo_data.rb` | 同上（12 行目） |
| `spec/models/purification_time_spec.rb` | 同上（224 行目） |
| `spec/services/guest_demo_data_spec.rb` | 同上（23 行目） |
| `CLAUDE.md` | 「活動記録のフロー」節の Granter と `ActivityRecordForm` の段落を更新 |

Granter の spec を移すときは、`subject(:granter) { described_class.new(user) }` を削除し、`granter.call(record)` を `described_class.grant!(user, record)` に置き換える。

## テスト

既存のテストを移すだけで、テストを追加・削除しない。移設前後で次が成り立つことを確かめる。

- **テストの件数が変わらない**: 移設する example は、`activity_record_spec.rb` の 4 つの describe で 26 件、`purification_time_granter_spec.rb` で 17 件。`purification_reward_spec.rb` は最終的に 43 件になる。`bundle exec rspec` の全体の件数もコミット前後で変わらない
- **移動だけである**: `git diff --color-moved=zebra` で、移設したコードとテストが「移動」として表示され、名前の置き換え以外の変更がないことを確かめる
- **すべて green**: 各コミットの時点で `docker compose exec web bundle exec rspec` と `docker compose exec web bin/rubocop` が通る

## 完了条件

- [ ] `ActivityRecord` に浄化タイマーの付与関連の定数・メソッドが残っていない（`ACTIVITY_AT` / `activity_date` / `total_light_time_on` / `total_light_time_today` は除く）
- [ ] `app/services/purification_time_granter.rb` と その spec が存在しない
- [ ] リポジトリ内（`docs/superpowers/` の過去の設計書を除く）に `PurificationTimeGranter` / `sample_purification_minutes` / `purification_blocks` / `minutes_until_next_purification` / `PURIFICATION_BLOCK_MINUTES` / `PURIFICATION_TIME_TABLE` の参照が残っていない
- [ ] 付与される分数・ブロック数・表示分数が移設前と同一である（既存テストがそのまま通る）
- [ ] `CLAUDE.md` が新しい配置を指している
- [ ] issue #284 の本文に、Granter を統合する方針に変えた理由が追記されている
- [ ] `docker compose exec web bundle exec rspec` が green
- [ ] `docker compose exec web bin/rubocop` が clean

## スコープ外

- `blocks` の古いコメントの修正（別 issue）
- `GuestDemoData` の置き場所の見直し
- `ActivityRecordForm` の責務の見直し
