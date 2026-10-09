# 浄化タイマーの報酬ルールと付与を PurificationReward に統合する 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ActivityRecord` にある浄化タイマーの付与ルールと `PurificationTimeGranter` の付与処理を、テーブルを持たないモデル `PurificationReward` に挙動を変えずに統合する。

**Architecture:** `app/models/purification_reward.rb` に定数とクラスメソッドだけを持つ PORO を作る。コミット 1 で純粋なルールを `ActivityRecord` から移し、コミット 2 で Granter の `call` を `PurificationReward.grant!(user, activity_record)` として移して Granter を削除する。どちらのコミットも名前の置き換え以外は移動だけにする。

**Tech Stack:** Ruby 3.3.6 / Rails 8.1 / RSpec / Docker Compose（`web` コンテナ）

**Spec:** `docs/superpowers/specs/2026-10-09-purification-reward-design.md`

## Global Constraints

- 挙動を一切変えない。付与される分数・ブロック数・マイページの表示分数は移設前と同一
- テストを追加・削除しない。移すだけ（`purification_reward_spec.rb` は Task 1 後に 26 件、Task 2 後に 43 件）
- 名前の置き換え以外の変更を混ぜない（`blocks` の古いコメントもそのまま移す）
- `ActivityRecord::ACTIVITY_AT` / `activity_date` / `total_light_time_on` / `total_light_time_today` は動かさない
- 文字列はダブルクォート（`.rubocop.yml`）。コメント・コミットメッセージは日本語
- コミットメッセージは `<type>: <日本語の要約> #284` の形で、末尾に `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` を付ける（Claude-Session の URL 行は入れない）
- テスト・lint は `docker compose exec web` 経由で実行する。ファイル編集はホスト（macOS）で行うので `sed -i ''` を使う
- 作業ブランチは `refactor/purification-reward-284`（作成済み、設計書コミット c7f7e0c の上に積む）

## Review Focus

- **本番の eager load**: `app/models/purification_reward.rb` のファイル名とクラス名が Zeitwerk の規約どおりで、本番でも読み込めること → Task 2 Step 9 で `bin/rails zeitwerk:check` を実行する
- **古いスタブの取り残し**: `spec_helper.rb:37` で `verify_partial_doubles = true` なので、存在しないメソッドをスタブすると例外で落ちる。ただし rspec を部分的にしか流さないと見逃すので、各 Task の最後で全体を流し、Task 2 Step 9 で古い名前を grep する
- **同時保存での二重付与（`with_lock` の範囲）**: 既存テストは並行実行を検証していない。`grant!` の `with_lock` ブロックの中身が Granter の `call` と同一であることを、Task 2 Step 7 の `git diff --color-moved` で確かめる（テストは追加しない: Global Constraints）
- **付与で例外が出たときのロールバック**: `grant!` の `save!` が例外を投げたとき、`ActivityRecordForm#save` のトランザクションごと巻き戻る挙動は、呼び出しの差し替えだけなので変わらない。Task 2 Step 3 で Form の差分が 1 行だけであることを確かめる
- **呼び出し元の取り残し**: ビュー・JS・i18n・seeds・README に古い名前が残っていないこと → Task 2 Step 9 の grep の対象に含める

---

### Task 1: 付与ルールを `ActivityRecord` から `PurificationReward` へ移す（コミット 1）

**Files:**
- Create: `app/models/purification_reward.rb`
- Create: `spec/models/purification_reward_spec.rb`
- Modify: `app/models/activity_record.rb:90-134`（削除）
- Modify: `spec/models/activity_record_spec.rb:89-293`（削除）
- Modify: `app/services/purification_time_granter.rb:34,50`
- Modify: `app/controllers/mypages_controller.rb:9`
- Modify: `spec/services/purification_time_granter_spec.rb:10,66`
- Modify: `spec/forms/activity_record_form_spec.rb:168`
- Modify: `spec/requests/activity_records_spec.rb:200,222`
- Modify: `spec/system/activity_records_spec.rb:458`
- Modify: `spec/services/guest_user_builder_spec.rb:85`
- Modify: `CLAUDE.md:92`

**Interfaces:**
- Consumes: なし
- Produces:
  - `PurificationReward::BLOCK_MINUTES` → `Integer`（30）
  - `PurificationReward::TIME_TABLE` → `Array<Hash{minutes:, weight:}>`（frozen）
  - `PurificationReward.sample_minutes` → `Integer`（乱数）
  - `PurificationReward.blocks(minutes)` → `Integer`
  - `PurificationReward.sample_minutes_for(blocks)` → `Integer`（乱数。内部で `sample_minutes` を呼ぶので、これをスタブすれば固定できる）
  - `PurificationReward.minutes_until_next(total_minutes, granted_blocks = 0)` → `Integer`

- [ ] **Step 1: issue #284 の本文に方針の変更を追記する**

```bash
cd /Users/tatsuhirofuruta/workspace/get_the_time
gh issue view 284 --json body -q .body > "$TMPDIR/issue284.md"
cat >> "$TMPDIR/issue284.md" <<'EOF'

## 方針の変更（2026-10-09）

設計の議論で「移設先は `PurificationTimeGranter` ではない」という方針を見直し、**Granter も `PurificationReward` に統合する**ことにした。Granter の `call` は `PurificationReward.grant!(user, activity_record)` になり、`app/services/purification_time_granter.rb` は削除する。

- Granter を別クラスにしておく価値は「ルールと DB への反映を分けておける」点だけだが、純粋な部分の呼び出し元は Granter とマイページの 2 か所だけで、「浄化タイマーの付与は `PurificationReward` を見れば全部わかる」一貫性の方が大きい
- 統合後は入口が複数（`grant!` / `minutes_until_next` / `blocks` など）で大半が問い合わせなので、「入口が `call` ひとつの手続き」であるサービスではなく、モデル（`app/models/`、テーブルなしの PORO）に置く

詳細は設計書 `docs/superpowers/specs/2026-10-09-purification-reward-design.md` を参照。作業は「ルールの移設」「付与の移設」の 2 コミットに分け、どちらも移動だけにする。
EOF
gh issue edit 284 --body-file "$TMPDIR/issue284.md"
```

Expected: `https://github.com/TatsuhiroFuruta/get_the_time/issues/284` が出力される。

- [ ] **Step 2: 移設前のテスト件数を記録する**

```bash
docker compose exec web bundle exec rspec --dry-run | grep "examples"
docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb --dry-run | grep "examples"
```

Expected: 全体の件数（以後 `N_TOTAL` と呼ぶ）と `activity_record_spec.rb` の件数（以後 `N_AR`）を控える。

- [ ] **Step 3: テストを移す（失敗するテストを書く）**

`activity_record_spec.rb` の 89〜292 行目（`.sample_purification_minutes` から `.minutes_until_next_purification` までの 4 つの describe と区切りコメント）を、名前だけ置き換えて新しい spec へ移す。これらの describe は `user` / `light_time` を使っていないので、`let` は持ってこなくてよい。

```bash
cd /Users/tatsuhirofuruta/workspace/get_the_time
{
  printf 'require "rails_helper"\n\nRSpec.describe PurificationReward, type: :model do\n'
  sed -n 89,292p spec/models/activity_record_spec.rb \
    | sed -e 's/sample_purification_minutes/sample_minutes/g' \
          -e 's/purification_blocks/blocks/g' \
          -e 's/minutes_until_next_purification/minutes_until_next/g'
  printf 'end\n'
} > spec/models/purification_reward_spec.rb
sed -i '' 89,293d spec/models/activity_record_spec.rb
```

`sample_purification_minutes_for` は最初の置換で `sample_minutes_for` になる。

- [ ] **Step 4: 新しい spec が失敗することを確かめる**

```bash
docker compose exec web bundle exec rspec spec/models/purification_reward_spec.rb
```

Expected: FAIL（`NameError: uninitialized constant PurificationReward`）

- [ ] **Step 5: `PurificationReward` を作る**

`app/models/purification_reward.rb`（メソッドの中身とコメントは `activity_record.rb:90-133` のまま。定数の参照先だけ変える）:

```ruby
# 浄化タイマーの報酬（付与）のルールをまとめたクラス。テーブルは持たない。
#
# ブロックの粒度・抽選テーブル・ブロック数の計算・次の付与までの分数など、
# 活動記録の属性にも関連にも依存しない計算をここに置く。
class PurificationReward
  # 浄化タイマー付与の 1 ブロック（分）。この分数がたまるごとに抽選を 1 回引く。
  BLOCK_MINUTES = 30

  # 付与分数の重み付きテーブル（合計 100）
  TIME_TABLE = [
    { minutes: 8,  weight: 60 },
    { minutes: 10, weight: 30 },
    { minutes: 13, weight: 9  },
    { minutes: 15, weight: 1  }
  ].freeze

  # 1ブロック分の付与分数をランダム抽選
  def self.sample_minutes
    threshold = rand(100)
    cumulative = 0
    TIME_TABLE.each do |entry|
      cumulative += entry[:weight]
      return entry[:minutes] if threshold < cumulative
    end
    TIME_TABLE.last[:minutes]
  end

  # 累計分数から、消化済みのブロック数を求める。
  # 余りを翌日へ繰り越さない設計のため、付与済みブロック数は累計だけから導出できる。
  def self.blocks(minutes)
    [ minutes.to_i, 0 ].max / BLOCK_MINUTES
  end

  # blocks 回の抽選を引いた合計分数。乱数を含むため呼ぶたびに結果が変わる。
  def self.sample_minutes_for(blocks)
    return 0 if blocks <= 0

    blocks.times.sum { sample_minutes }
  end

  # 次の付与までの残り分数（マイページ表示用）。累計 0 分でも 30 を返す。
  #
  # 累計の余りではなく「払い出し済みブロック数の次の閾値」から逆算する。活動記録を
  # 削除すると累計だけが下がるため、余りだけを見ると実際より短い分数を表示してしまう。
  def self.minutes_until_next(total_minutes, granted_blocks = 0)
    next_threshold = (granted_blocks.to_i + 1) * BLOCK_MINUTES

    [ next_threshold - [ total_minutes.to_i, 0 ].max, 0 ].max
  end
end
```

`sample_minutes_for` の引数 `blocks` はメソッド `blocks` と同名だが、メソッド内ではローカル変数が優先され、メソッド `blocks` は呼んでいないので問題ない（移設前と同じ形を保つため名前は変えない）。

- [ ] **Step 6: 新しい spec が通ることを確かめる**

```bash
docker compose exec web bundle exec rspec spec/models/purification_reward_spec.rb
```

Expected: `26 examples, 0 failures`

- [ ] **Step 7: `ActivityRecord` から定数とメソッドを削除する**

`app/models/activity_record.rb` の 90〜134 行目（`# 浄化タイマー付与の 1 ブロック（分）。…` から `minutes_until_next_purification` の `end` とその直後の空行まで）を削除する。

```bash
sed -n 90p app/models/activity_record.rb   # → "  # 浄化タイマー付与の 1 ブロック（分）。…" であること
sed -n 134,135p app/models/activity_record.rb  # → 空行、"  # 検索可能カラムの登録" であること
sed -i '' 90,134d app/models/activity_record.rb
```

- [ ] **Step 8: 呼び出し元とスタブ先を差し替える**

`app/services/purification_time_granter.rb`:

```ruby
      minutes = PurificationReward.sample_minutes_for(blocks)
```
```ruby
    [ PurificationReward.blocks(total) - granted, 0 ].max
```

`app/controllers/mypages_controller.rb:9`:

```ruby
    @minutes_to_next_purification = PurificationReward.minutes_until_next(
```

スタブ先（6 か所）:

```bash
sed -i '' \
  -e 's/allow(ActivityRecord)\.to receive(:sample_purification_minutes)/allow(PurificationReward).to receive(:sample_minutes)/' \
  -e 's/expect(ActivityRecord)\.to have_received(:sample_purification_minutes)/expect(PurificationReward).to have_received(:sample_minutes)/' \
  spec/services/purification_time_granter_spec.rb \
  spec/forms/activity_record_form_spec.rb \
  spec/requests/activity_records_spec.rb \
  spec/system/activity_records_spec.rb \
  spec/services/guest_user_builder_spec.rb
grep -rn "sample_purification_minutes\|purification_blocks\|minutes_until_next_purification\|PURIFICATION_" app spec lib db config
```

Expected: grep の出力なし。

- [ ] **Step 9: CLAUDE.md の付与ルールの段落を更新する**

`CLAUDE.md:92` の行を次に置き換える:

```markdown
- 浄化タイマーの付与は**1 セッション単位ではなく、その日の光の時間の累計 30 分ごと**です。付与のルールは `PurificationReward`（`app/models/`、テーブルを持たない PORO）のクラスメソッドにまとめてあります。`blocks(minutes)` が累計分数から消化済みブロック数（`floor(累計 / 30)`）を求め、`sample_minutes_for(blocks)` がブロック数だけ `sample_minutes`（`TIME_TABLE` の重み付き抽選）を引いて合計します。**後者は乱数を含むため、同じ入力でも呼ぶたびに結果が変わります。表示・保存で複数回呼ばないこと。**
```

- [ ] **Step 10: 全体のテストと lint を流す**

```bash
docker compose exec web bundle exec rspec
docker compose exec web bundle exec rspec --dry-run | grep "examples"
docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb --dry-run | grep "examples"
docker compose exec web bin/rubocop
```

Expected: 全件 green。全体の件数が `N_TOTAL` のまま。`activity_record_spec.rb` は `N_AR - 26` 件。rubocop は `no offenses detected`。

- [ ] **Step 11: 移動だけであることを確かめる**

```bash
git add -A
git diff --cached --color-moved=zebra --color-moved-ws=allow-indentation-change --stat
git diff --cached --color-moved=zebra --color-moved-ws=allow-indentation-change
```

Expected: `activity_record.rb` と `activity_record_spec.rb` から消えた行が、新しいファイル側で「移動」の色になっている。移動の色にならない行は、名前の置き換え・クラス冒頭のコメント・`RSpec.describe` の行・CLAUDE.md・呼び出し元の差し替えだけであること。

- [ ] **Step 12: コミット**

```bash
git commit -m "refactor: 浄化タイマーの付与ルールを ActivityRecord から PurificationReward へ移す #284

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `PurificationTimeGranter` を `PurificationReward.grant!` に統合する（コミット 2）

**Files:**
- Modify: `app/models/purification_reward.rb`（`grant!` と `unpaid_blocks` を追加）
- Delete: `app/services/purification_time_granter.rb`
- Modify: `app/forms/activity_record_form.rb:68`
- Modify: `spec/models/purification_reward_spec.rb`（`describe ".grant!"` を追加）
- Delete: `spec/services/purification_time_granter_spec.rb`
- Modify: `spec/services/guest_user_builder_spec.rb:95`
- Modify: `app/models/purification_time.rb:51`、`app/services/guest_demo_data.rb:12`、`spec/models/purification_time_spec.rb:224`、`spec/services/guest_demo_data_spec.rb:23`（コメント）
- Modify: `CLAUDE.md:96,100`

**Interfaces:**
- Consumes: Task 1 の `PurificationReward.blocks` / `PurificationReward.sample_minutes_for` / `PurificationReward.sample_minutes`
- Produces: `PurificationReward.grant!(user, activity_record)` → `Integer`（付与した分数。付与がなければ 0）。`activity_record` は保存済みであること。失敗時は `ActiveRecord::RecordInvalid` を投げる

- [ ] **Step 1: テストを移す（失敗するテストを書く）**

`purification_time_granter_spec.rb` の 4〜20 行目（`let` / スタブ / `create_record`）と 23〜278 行目（`describe "#call"` の中身）を、`purification_reward_spec.rb` の末尾に `describe ".grant!"` として移す。7〜8 行目の `subject(:granter)` と直後の空行は不要になるので移さない。

```bash
cd /Users/tatsuhirofuruta/workspace/get_the_time
src=spec/services/purification_time_granter_spec.rb
dst=spec/models/purification_reward_spec.rb
sed -n 7p "$src"    # → "  subject(:granter) { described_class.new(user) }" であること
sed -n 22p "$src"   # → '  describe "#call" do' であること
sed -n 279p "$src"  # → "  end" であること（describe "#call" の閉じ）

sed -i '' '$d' "$dst"   # 末尾の "end" を一旦外す
{
  printf '\n  # =========================================================\n'
  printf '  # .grant!\n'
  printf '  # =========================================================\n'
  printf '  describe ".grant!" do\n'
  sed -n '4,6p;9,20p' "$src" \
    | sed -e 's/^\(.\)/  \1/' \
          -e 's/# Granter は保存済み/# grant! は保存済み/'
  printf '\n'
  sed -n 23,278p "$src" \
    | sed -e 's/granter\.call(/described_class.grant!(user, /g'
  printf '  end\nend\n'
} >> "$dst"
grep -n "granter\|Granter" "$dst"
```

Expected: grep の出力なし。`sed -e 's/^\(.\)/  \1/'` は空行以外の行だけ 2 文字字下げする（`let` などが `describe ".grant!"` の内側に入るため）。

- [ ] **Step 2: 新しい describe が失敗することを確かめる**

```bash
docker compose exec web bundle exec rspec spec/models/purification_reward_spec.rb
```

Expected: FAIL（`NoMethodError: undefined method 'grant!' for class PurificationReward` が 17 件。既存の 26 件は通る）

- [ ] **Step 3: `grant!` を追加し、Form を差し替える**

`app/models/purification_reward.rb` の `minutes_until_next` の後、最後の `end` の前に追加する（コメントは Granter のクラスコメントと `call` / `unpaid_blocks` のコメントをそのまま移す。`@user` を引数の `user` に、`ActivityRecord.purification_blocks` などを自クラスのメソッドに変えるだけ）:

```ruby

  # 活動記録の登録に伴う浄化タイマー時間の付与。
  #
  # 付与の単位は「その日の光の時間の累計 30 分ごとに 1 ブロック」。その日の累計から求めた
  # ブロック数と、`purification_times` に記録した払い出し済みブロック数の差を取り、
  # まだ払い出していない分だけを付与する。
  #
  # 累計は活動記録から導出するので、記録が削除されると減る。払い出し済み数まで累計から
  # 導出すると、29 分ためた状態で 1 分の記録を作っては消す操作で 1 分ごとに 1 ブロック
  # 稼げてしまうため、払い出した実績だけは台帳として保存する。
  #
  # 付与分数は 30 分ブロックごとの重み付き抽選（乱数）で決まるため、計算は必ず 1 回だけ行う。
  # 付与した分数を戻り値として返すため、フラッシュ表示など呼び出し側が「実際に付与した値」を
  # そのまま利用でき、再計算による表示と保存のズレを防ぐ。
  #
  # 保存済みの activity_record を受け取り、その日の累計に応じた浄化タイマー時間を
  # 付与して、付与した分数を返す。付与が発生しないときは 0 を返す。
  #
  # 累計と台帳の読み取りから加算までを with_lock の中で行う。読み取りをロックの外に置くと、
  # 2 件の活動記録が同時に保存されたときに両方が同じ値を読み、同じブロックを二重に
  # 付与しうる。
  def self.grant!(user, activity_record)
    user.with_lock do
      day = ActivityRecord.activity_date(activity_record)
      purification_time = user.purification_time || user.build_purification_time
      granted = purification_time.granted_blocks_for(day)

      blocks = unpaid_blocks(user, day, granted)
      next 0 if blocks <= 0

      minutes = sample_minutes_for(blocks)
      purification_time.add_time(minutes * 60)
      purification_time.granted_blocks_date = day
      purification_time.granted_blocks_count = granted + blocks
      purification_time.save!
      minutes
    end
  end

  # その日の累計から求めたブロック数のうち、まだ払い出していない分。
  # 削除で累計が下がっても払い出し済み数は減らないため、負にならないよう 0 で止める。
  def self.unpaid_blocks(user, day, granted)
    total = ActivityRecord.total_light_time_on(user, day)

    [ blocks(total) - granted, 0 ].max
  end
  private_class_method :unpaid_blocks
```

`unpaid_blocks` は `private_class_method` なので、`grant!` の中ではレシーバを付けずに呼ぶ（`PurificationReward.unpaid_blocks(...)` と書くと `NoMethodError`）。`grant!` 内のローカル変数 `blocks` はメソッド `blocks` と同名だが、`grant!` 内ではメソッド `blocks` を呼んでいないので問題ない（移設前と同じ変数名を保つ）。

`app/forms/activity_record_form.rb:68`:

```ruby
      @granted_purification_minutes = PurificationReward.grant!(user, activity_record)
```

`git diff app/forms/activity_record_form.rb` で変更がこの 1 行だけであることを確かめる。

- [ ] **Step 4: 新しい spec が通ることを確かめる**

```bash
docker compose exec web bundle exec rspec spec/models/purification_reward_spec.rb
```

Expected: `43 examples, 0 failures`

- [ ] **Step 5: Granter と その spec を削除し、残りの参照を差し替える**

```bash
git rm -q app/services/purification_time_granter.rb spec/services/purification_time_granter_spec.rb
sed -i '' 's/PurificationTimeGranter\.new(user)\.call(record)/PurificationReward.grant!(user, record)/' spec/services/guest_user_builder_spec.rb
sed -i '' 's/PurificationTimeGranter/PurificationReward.grant!/' \
  app/models/purification_time.rb \
  app/services/guest_demo_data.rb \
  spec/models/purification_time_spec.rb \
  spec/services/guest_demo_data_spec.rb
git diff app/models/purification_time.rb app/services/guest_demo_data.rb spec/models/purification_time_spec.rb spec/services/guest_demo_data_spec.rb
```

Expected: 4 ファイルとも、コメント中の `PurificationTimeGranter` が `PurificationReward.grant!` に変わった 1 行ずつの差分。`guest_demo_data.rb:12` は「瞬間に PurificationReward.grant! が floor(当日累計 / 30) 個のブロックを払い出して」、`purification_time.rb:51` は「保存は呼び出し側（PurificationReward.grant!）が」となる。

- [ ] **Step 6: CLAUDE.md の Granter と Form の段落を更新する**

`CLAUDE.md:96` の段落を次に置き換える:

```markdown
浄化タイマーへの「加算（副作用）」も `PurificationReward` が担います。`PurificationReward.grant!(user, activity_record)` が**保存済みの `ActivityRecord` を受け取り**、`user.with_lock` 内でその日の累計を読んで差分ブロック分を `PurificationTime` に加算し、**付与した実分数を返します**。累計の読み取りをロックの外に出すと同時保存で二重付与が起きるため、読み取りから加算までをロック内に閉じています。以前は `after_create :grant_purification_time` コールバックで付与していましたが、付与値を呼び出し側へ返せず、コントローラが表示用に再計算して乱数がズレる不具合があったため、戻り値を返す形に移しました（付与は 1 回だけ計算し、その戻り値を表示にも使う）。その後サービス `PurificationTimeGranter` として切り出していましたが、ルールと付与を 1 か所にまとめるため `PurificationReward` に統合しました（#284）。**`ActivityRecord` を直接 `create` しても付与は走りません。**
```

`CLAUDE.md:100` の `` `PurificationTimeGranter` による付与`` を `` `PurificationReward.grant!` による付与`` に置き換える。

- [ ] **Step 7: 移動だけであることを確かめる**

```bash
git add -A
git diff --cached --color-moved=zebra --color-moved-ws=allow-indentation-change
```

Expected: `purification_time_granter.rb` の `call` / `unpaid_blocks` の本体、`purification_time_granter_spec.rb` の 23〜278 行目が、`purification_reward.rb` / `purification_reward_spec.rb` 側で「移動」の色になっている。移動の色にならない行が、`@user` → `user`、`ActivityRecord.xxx` → 自クラスのメソッド、`granter.call(` → `described_class.grant!(user, `、`def` の行、コメント中の名前、CLAUDE.md、呼び出し元の差し替えだけであること。特に `user.with_lock do` から対応する `end` までの行の並びが Granter と同一であること。

- [ ] **Step 8: 全体のテストと lint を流す**

```bash
docker compose exec web bundle exec rspec
docker compose exec web bundle exec rspec --dry-run | grep "examples"
docker compose exec web bin/rubocop
```

Expected: 全件 green。全体の件数が `N_TOTAL` のまま。rubocop は `no offenses detected`。

- [ ] **Step 9: 取り残しと eager load を確かめる**

```bash
git grep -n "PurificationTimeGranter\|purification_time_granter\|sample_purification_minutes\|purification_blocks\|minutes_until_next_purification\|PURIFICATION_BLOCK_MINUTES\|PURIFICATION_TIME_TABLE" -- . ':!docs/superpowers'
docker compose exec web bin/rails zeitwerk:check
```

Expected: `git grep` の出力なし（`docs/superpowers/` の過去の設計書・計画書は当時の記録なので除外）。`zeitwerk:check` は `All is good!`。

- [ ] **Step 10: コミット**

```bash
git commit -m "refactor: PurificationTimeGranter を PurificationReward.grant! に統合する #284

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: PR 前のレビューと PR 作成

**Files:** なし（レビューで指摘があれば該当ファイル）

- [ ] **Step 1: 設計書の完了条件を確認する**

`docs/superpowers/specs/2026-10-09-purification-reward-design.md` の「完了条件」を 1 つずつ確認し、すべて満たしていることを確かめる。

- [ ] **Step 2: コードレビューを通す**

superpowers:requesting-code-review でブランチ全体（main との差分）をレビューする。観点は「名前の置き換え以外の挙動の変化がないこと」と、上の Review Focus の 5 点。指摘があれば修正して該当 Task の Step 8 相当（全体のテスト・lint）を流し直し、別コミットにする。

- [ ] **Step 3: push して PR を作る（ユーザーの確認を取ってから）**

```bash
git push -u origin refactor/purification-reward-284
gh pr create --base main --title "refactor: 浄化タイマーの報酬ルールと付与を PurificationReward に統合する #284" --body "$(cat <<'EOF'
## 概要

closes #284

`ActivityRecord` にあった浄化タイマーの付与ルールと `PurificationTimeGranter` の付与処理を、テーブルを持たないモデル `PurificationReward` に統合しました。挙動は変えていません。

## 変更内容

- コミット 1: 付与ルール（定数 2 つ・クラスメソッド 4 つ）を `ActivityRecord` から `PurificationReward` へ移設
- コミット 2: `PurificationTimeGranter#call` を `PurificationReward.grant!(user, activity_record)` として移設し、Granter を削除

どちらのコミットも名前の置き換え以外は移動だけです。`git diff --color-moved=zebra --color-moved-ws=allow-indentation-change` で確認できます。

## 判断の経緯

Granter を統合する理由と、サービスではなくモデルに置く理由は設計書 `docs/superpowers/specs/2026-10-09-purification-reward-design.md` にまとめています。

## スコープ外

- `PurificationReward.blocks` のコメント「余りを翌日へ繰り越さない設計のため、付与済みブロック数は累計だけから導出できる」は #251 の台帳導入以降、現状と合っていません。この PR は移動だけにするためそのまま移しており、別 issue で直します

## テスト

- テストは追加・削除せず移設のみ（`spec/models/purification_reward_spec.rb` に 43 件）。全体の件数は移設前後で同じ
- `bundle exec rspec` green / `bin/rubocop` clean / `bin/rails zeitwerk:check` OK

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: 古いコメントを直す issue を立てる（ユーザーの確認を取ってから）**

`PurificationReward.blocks` のコメントが #251 以降の現状と合っていないことを、別 issue として起票する。
