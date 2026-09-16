# 浄化タイマーの1日累計付与 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 浄化タイマーの付与単位を「1 セッションの活動時間」から「1 日の累計活動時間」に変え、30 分に満たない活動が切り捨てられないようにする。

**Architecture:** 新しいカラムは持たない。「余りを翌日へ繰り越さない」ため、付与済みブロック数は当日累計から `floor(累計 / 30)` で導出できる。`PurificationTimeGranter` が保存済みの `ActivityRecord` を受け取り、その日の累計（自分を含む）と、自分を引いた累計のブロック数の差を取って、新たに越えたぶんだけを付与する。「その活動がどの日のものか」の判定は `created_at`（送信時刻）から `ended_at`（活動の終了時刻）へ移し、モデルの定数 1 つに集約する。

**Tech Stack:** Rails 8.1 / PostgreSQL / Hotwire / Tailwind CSS v4 / RSpec + FactoryBot + Capybara + Selenium

**Spec:** `docs/superpowers/specs/2026-09-09-daily-cumulative-purification-design.md`

**関連:** issue [#251](https://github.com/TatsuhiroFuruta/get_the_time/issues/251) / ブランチ `feat/daily-cumulative-purification-251`

## Global Constraints

- UI 文言・コメント・フラッシュメッセージはすべて**日本語**（デフォルトロケール `:ja`、`config/application.rb`）。
- 文字列は**ダブルクォート**。`spec/**/*` も対象（`.rubocop.yml`）。
- テストは **RSpec**（Minitest ではない）。`bin/rails test` は使わない。
- コマンドは Docker 前提で `docker compose exec web` を前置する（ローカルに直接 Ruby がある場合は外す）。
- タイムゾーンは **`config.time_zone = "Tokyo"`**。「1 日」は常に JST 基準。
- `ActiveSupport::Testing::TimeHelpers`（`travel_to` / `freeze_time`）は `spec/rails_helper.rb` でグローバルに include 済み。`require` 不要。
- **`Capybara.ignore_hidden_elements = false`**（`spec/support/capybara.rb`）。System Spec で表示・非表示を見るときは `visible: true` / `visible: :all` を明示する。
- **マイグレーションは書かない。** 本計画でスキーマは変更しない。
- 1 ブロック = **30 分**、抽選テーブル `PURIFICATION_TIME_TABLE`（8 分 60% / 10 分 30% / 13 分 9% / 15 分 1%）は**変更しない**。
- `ActivityRecord` を直接 `create` しても付与は走らない（コールバックではなくサービス経由）。この性質は維持する。

## File Structure

| ファイル | 役割 | 変更内容 |
|---|---|---|
| `app/models/activity_record.rb` | 活動記録。日付の定義と付与計算の純粋関数を持つ | `ACTIVITY_AT` 定数と `activity_on` スコープを追加、`today` / `within_last_days` / `daily_series` をそれに寄せる、`total_light_time_on` を追加、付与計算を 3 つの純粋関数に分解、`calculate_purification_time` を削除 |
| `app/services/purification_time_granter.rb` | 浄化タイマーへの加算（副作用） | `call(total_duration)` → `call(activity_record)`。当日累計の読み取りを `with_lock` 内へ |
| `app/forms/activity_record_form.rb` | 活動記録の書き込み経路 | `create!` の戻り値を Granter に渡す |
| `app/controllers/mypages_controller.rb` | マイページ | `@minutes_to_next_purification` を追加 |
| `app/views/mypages/_pomodoro_start.html.erb` | 今日の光の時間とスタートボタン | 「次の浄化タイマーまで あと○分」を追加 |
| `spec/models/activity_record_spec.rb` | モデルの単体テスト | 日付基準の変更で落ちる 7 箇所を修正、新しい純粋関数の describe を追加、`calculate_purification_time` の describe を削除 |
| `spec/services/purification_time_granter_spec.rb` | 付与サービスのテスト | 全面改訂 |
| `spec/forms/activity_record_form_spec.rb` | フォームのテスト | 累計ベースの付与を検証する describe を追加 |
| `spec/system/purification_times_spec.rb` | 浄化タイマーの System Spec | 進捗表示のテストを追加、既存 1 件の assertion を精密化 |
| `app/views/static_pages/how_to_use/_step3.html.erb` | 使い方ページ（活動時間の計測） | マイページの新しい表示の説明を追加 |
| `app/views/static_pages/how_to_use/_step4.html.erb` | 使い方ページ（活動記録の登録） | 55 行目の「30分毎にランダムで付与」を累計ベースの説明に更新 |
| `README.md` | ドメイン仕様 | 117 行目の付与ルールを更新 |
| `CLAUDE.md` | 開発ガイド | 「活動記録のフロー」節を更新 |

新しいファイルは作らない。**`spec/system/mypages_spec.rb` は作らない** — マイページ用の System Spec / Request Spec は存在せず、`visit mypage_path` を持つ既存ファイルは `spec/system/purification_times_spec.rb` である。追加する表示も浄化タイマーに関するものなので、そこが置き場所になる。

タスクの順序は「日付の土台 → 計算部品 → それらを使う付与ロジック → 表示 → ドキュメント」。各タスクの終了時点で全テストが green になるよう、`calculate_purification_time` の削除は**それを使う最後の呼び出し元が消える Task 3 まで行わない**。

---

### Task 1: 日付の基準を `ended_at` に統一する

**Files:**
- Modify: `app/models/activity_record.rb:16-29`（`today` / `within_last_days` / `total_light_time_today`）, `:51`（`daily_series` の bucket）
- Test: `spec/models/activity_record_spec.rb`

**Interfaces:**
- Consumes: 既存の `db/schema.rb` のカラム（`ended_at` は NULL 許容、`created_at` は NOT NULL）
- Produces:
  - 定数 `ActivityRecord::ACTIVITY_AT`（String。SQL 式 `"COALESCE(activity_records.ended_at, activity_records.created_at)"`）
  - スコープ `ActivityRecord.activity_on(date)` → `ActiveRecord::Relation`。`date` は `Date`
  - `ActivityRecord.total_light_time_on(user, date)` → `Integer`（分）
  - `ActivityRecord.total_light_time_today(user)` → `Integer`（分）。シグネチャ据え置き
  - Task 3 の `PurificationTimeGranter` は `total_light_time_on` を使う

- [x] **Step 1: 失敗するテストを書く**

`spec/models/activity_record_spec.rb` の `.total_light_time_today` の `describe` ブロック（`context "別ユーザーの記録は集計に含まないこと"` の `end` の直後、`# before_save: calculate_desired_self_percentage` のコメント行の手前）に、以下の `describe` を丸ごと挿入する。

```ruby
  # =========================================================
  # .total_light_time_on
  # =========================================================
  describe ".total_light_time_on" do
    subject { described_class.total_light_time_on(user, Date.new(2026, 9, 9)) }

    around { |example| travel_to(Time.zone.local(2026, 9, 9, 12, 0, 0)) { example.run } }

    context "指定日に終わった記録があるとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, total_duration: 30,
                                 started_at: Time.zone.local(2026, 9, 9, 10, 0, 0),
                                 ended_at:   Time.zone.local(2026, 9, 9, 10, 30, 0))
      end

      it { is_expected.to eq 30 }
    end

    context "活動は前日に終わり、記録の送信だけが指定日になったとき" do
      before do
        record = create(:activity_record, user: user, light_time: light_time, total_duration: 50,
                                          started_at: Time.zone.local(2026, 9, 8, 23, 0, 0),
                                          ended_at:   Time.zone.local(2026, 9, 8, 23, 50, 0))
        # 日付が変わってから活動記録を送信したケース
        record.update_column(:created_at, Time.zone.local(2026, 9, 9, 0, 5, 0))
      end

      it "指定日の累計に含まれないこと" do
        is_expected.to eq 0
      end
    end

    context "0 時をまたいで指定日に終わったセッションがあるとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, total_duration: 30,
                                 started_at: Time.zone.local(2026, 9, 8, 23, 45, 0),
                                 ended_at:   Time.zone.local(2026, 9, 9, 0, 15, 0))
      end

      it "終了した日の累計に含まれること" do
        is_expected.to eq 30
      end
    end

    context "ended_at が NULL のとき" do
      before do
        record = create(:activity_record, user: user, light_time: light_time, total_duration: 45)
        record.update_columns(ended_at: nil, created_at: Time.zone.local(2026, 9, 9, 10, 0, 0))
      end

      it "created_at にフォールバックして集計されること" do
        is_expected.to eq 45
      end
    end

    context "別ユーザーの記録があるとき" do
      let(:other_user)  { create(:user) }
      let(:other_light) { create(:light_time, :current, user: other_user) }

      before do
        create(:activity_record, user: other_user, light_time: other_light, total_duration: 999,
                                 started_at: Time.zone.local(2026, 9, 9, 10, 0, 0),
                                 ended_at:   Time.zone.local(2026, 9, 9, 10, 30, 0))
      end

      it "集計に含まれないこと" do
        is_expected.to eq 0
      end
    end
  end
```

- [x] **Step 2: テストが失敗することを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb -e ".total_light_time_on"`

Expected: FAIL。`NoMethodError: undefined method 'total_light_time_on'`。

- [x] **Step 3: モデルに日付基準を実装する**

`app/models/activity_record.rb` の 16〜29 行目（`scope :today` から `total_light_time_today` の `end` まで）を、以下で丸ごと置き換える。

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

  # 指定日（JST）の光の時間の合計分数。付与ロジックは「そのレコードの日」を必要とし、
  # 必ずしも今日とは限らないため日付を引数に取る。
  def self.total_light_time_on(user, date)
    where(user: user)
      .activity_on(date)
      .sum(:total_duration)
      .to_i
  end

  def self.total_light_time_today(user)
    total_light_time_on(user, Date.current)
  end
```

続いて `daily_series` の日付バケット（51 行目）を同じ式に揃える。

置き換え前:

```ruby
    bucket = Arel.sql("DATE((created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Tokyo')")
```

置き換え後:

```ruby
    bucket = Arel.sql("DATE((#{ACTIVITY_AT} AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Tokyo')")
```

- [x] **Step 4: 新しいテストが通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb -e ".total_light_time_on"`

Expected: PASS（5 examples）。

- [x] **Step 5: 基準日の変更で落ちる既存テストを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb`

Expected: FAIL が 7 件前後。`evaluation_averages` / `fatigue_average` / `desired_self_percentage_average` の「30日より古い記録は集計に含めないこと」と、`daily_series` の 4 つの context。

原因は**テストの書き方が古いだけ**である。ファクトリが `ended_at { Time.current }` を設定しているため、`created_at` だけを過去に倒しても `COALESCE` は `ended_at`（今日）を拾う。プロダクションコードの不具合ではない。

- [x] **Step 6: 既存テストを新しい基準に合わせる**

`spec/models/activity_record_spec.rb` の以下 7 箇所を修正する。いずれも `created_at` だけを動かしていたものを、`ended_at` も同じ時刻に揃える。

**(1) `.evaluation_averages` の「30日より古い記録は集計に含めないこと」**

置き換え前:

```ruby
        old_record = build(:activity_record, :low_rating, user: user, light_time: light_time)
        old_record.save!
        old_record.update_column(:created_at, 31.days.ago)
```

置き換え後:

```ruby
        old_record = build(:activity_record, :low_rating, user: user, light_time: light_time)
        old_record.save!
        old_record.update_columns(created_at: 31.days.ago, ended_at: 31.days.ago)
```

**(2) `.fatigue_average` の「30日より古い記録は集計に含めないこと」**

置き換え前:

```ruby
        old_record = build(:activity_record, user: user, light_time: light_time, fatigue: 5)
        old_record.save!
        old_record.update_column(:created_at, 31.days.ago)
```

置き換え後:

```ruby
        old_record = build(:activity_record, user: user, light_time: light_time, fatigue: 5)
        old_record.save!
        old_record.update_columns(created_at: 31.days.ago, ended_at: 31.days.ago)
```

**(3) `.desired_self_percentage_average` の「30日より古い記録は集計に含めないこと」**

置き換え前:

```ruby
        old_record = build(:activity_record, user: user, light_time: light_time,
                                             total_duration: 100, idle_duration: 80)
        old_record.save!
        old_record.update_column(:created_at, 31.days.ago)
```

置き換え後:

```ruby
        old_record = build(:activity_record, user: user, light_time: light_time,
                                             total_duration: 100, idle_duration: 80)
        old_record.save!
        old_record.update_columns(created_at: 31.days.ago, ended_at: 31.days.ago)
```

**(4) `.daily_series` の「JST で日跨ぎする UTC レコード（JST 0:30 など）があるとき」**

置き換え前:

```ruby
        record.update_column(:created_at, Time.zone.local(2026, 5, 28, 0, 30, 0))
```

置き換え後:

```ruby
        record.update_columns(created_at: Time.zone.local(2026, 5, 28, 0, 30, 0),
                              ended_at:   Time.zone.local(2026, 5, 28, 0, 30, 0))
```

**(5)(6) `.daily_series` の「複数日にレコードがあるとき」**

置き換え前:

```ruby
        r1 = create(:activity_record, user: user, light_time: light_time, total_duration: 60)
        r1.update_column(:created_at, Time.zone.local(2026, 5, 26, 10, 0, 0))
        r2 = create(:activity_record, user: user, light_time: light_time, total_duration: 120)
        r2.update_column(:created_at, Time.zone.local(2026, 5, 27, 10, 0, 0))
```

置き換え後:

```ruby
        r1 = create(:activity_record, user: user, light_time: light_time, total_duration: 60)
        r1.update_columns(created_at: Time.zone.local(2026, 5, 26, 10, 0, 0),
                          ended_at:   Time.zone.local(2026, 5, 26, 10, 0, 0))
        r2 = create(:activity_record, user: user, light_time: light_time, total_duration: 120)
        r2.update_columns(created_at: Time.zone.local(2026, 5, 27, 10, 0, 0),
                          ended_at:   Time.zone.local(2026, 5, 27, 10, 0, 0))
```

**(7) `.daily_series` の「30日より古い記録は集計に含めないこと」**

置き換え前:

```ruby
        old_record = build(:activity_record, user: user, light_time: light_time, total_duration: 60)
        old_record.save!
        old_record.update_column(:created_at, 31.days.ago)
```

置き換え後:

```ruby
        old_record = build(:activity_record, user: user, light_time: light_time, total_duration: 60)
        old_record.save!
        old_record.update_columns(created_at: 31.days.ago, ended_at: 31.days.ago)
```

- [x] **Step 7: モデルの全テストが通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb`

Expected: PASS（0 failures）。

- [x] **Step 8: 他の spec に波及していないことを確認する**

Run: `docker compose exec web bundle exec rspec spec/models spec/requests spec/helpers`

Expected: PASS（0 failures）。`total_light_time_today` のシグネチャは変えていないので、マイページ側は影響を受けない。

- [x] **Step 9: RuboCop を通す**

Run: `docker compose exec web bin/rubocop app/models/activity_record.rb spec/models/activity_record_spec.rb`

Expected: no offenses。

- [x] **Step 10: Brakeman を通す**

Run: `docker compose exec web bin/brakeman --no-pager`

Expected: `No warnings found`。

**もし SQL injection の警告が出た場合**、`ACTIVITY_AT` の文字列補間が原因である。定数化をやめ、3 箇所（`activity_on` / `within_last_days` / `daily_series` の bucket）に SQL リテラルを直書きする形へ切り替える。DRY より CI が通ることを優先する。その場合 `ACTIVITY_AT` の定義と、それを参照するコメントも削除すること。

- [x] **Step 11: コミット**

```bash
git add app/models/activity_record.rb spec/models/activity_record_spec.rb
git commit -m "$(cat <<'EOF'
feat: 活動記録の日付基準を created_at から ended_at に変更 #251

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 付与計算を純粋関数に分解する

**Files:**
- Modify: `app/models/activity_record.rb`（`PURIFICATION_TIME_TABLE` の直前と `sample_purification_minutes` の直後）
- Test: `spec/models/activity_record_spec.rb`

**Interfaces:**
- Consumes: 既存の `ActivityRecord.sample_purification_minutes`（`PURIFICATION_TIME_TABLE` の重み付き抽選。乱数）
- Produces:
  - 定数 `ActivityRecord::PURIFICATION_BLOCK_MINUTES` = `30`
  - `ActivityRecord.purification_blocks(minutes)` → `Integer`（純粋。負値・nil は 0 扱い）
  - `ActivityRecord.sample_purification_minutes_for(blocks)` → `Integer`（乱数。`blocks` 回抽選した合計分数）
  - `ActivityRecord.minutes_until_next_purification(total_minutes)` → `Integer`（純粋。1〜30）
  - Task 3 が前 2 つ、Task 4 が最後の 1 つを使う

**既存の `calculate_purification_time` はこのタスクでは削除しない。** まだ `PurificationTimeGranter` が使っており、消すとテストが落ちる。削除は Task 3 で行う。

- [x] **Step 1: 失敗するテストを書く**

`spec/models/activity_record_spec.rb` の `.sample_purification_minutes` の `describe` ブロックの直後（`# .calculate_purification_time` のコメント行の手前）に、以下を挿入する。

```ruby
  # =========================================================
  # .purification_blocks
  # =========================================================
  describe ".purification_blocks" do
    subject { described_class.purification_blocks(minutes) }

    context "nil のとき" do
      let(:minutes) { nil }
      it { is_expected.to eq 0 }
    end

    context "0 分のとき" do
      let(:minutes) { 0 }
      it { is_expected.to eq 0 }
    end

    context "29 分のとき" do
      let(:minutes) { 29 }
      it { is_expected.to eq 0 }
    end

    context "30 分のとき" do
      let(:minutes) { 30 }
      it { is_expected.to eq 1 }
    end

    context "59 分のとき" do
      let(:minutes) { 59 }
      it { is_expected.to eq 1 }
    end

    context "60 分のとき" do
      let(:minutes) { 60 }
      it { is_expected.to eq 2 }
    end

    context "265 分（4 時間 25 分）のとき" do
      let(:minutes) { 265 }
      it { is_expected.to eq 8 }
    end

    context "負の値のとき" do
      let(:minutes) { -5 }

      # Ruby の整数除算は負の無限大方向に丸まる（-5 / 30 == -1）ため、
      # ガードがないとブロック数が水増しされる
      it { is_expected.to eq 0 }
    end
  end

  # =========================================================
  # .sample_purification_minutes_for
  # =========================================================
  describe ".sample_purification_minutes_for" do
    subject { described_class.sample_purification_minutes_for(blocks) }

    before { allow(described_class).to receive(:sample_purification_minutes).and_return(10) }

    context "0 ブロックのとき" do
      let(:blocks) { 0 }

      it { is_expected.to eq 0 }

      it "抽選を引かないこと" do
        subject
        expect(described_class).not_to have_received(:sample_purification_minutes)
      end
    end

    context "負のブロック数のとき" do
      let(:blocks) { -1 }
      it { is_expected.to eq 0 }
    end

    context "1 ブロックのとき" do
      let(:blocks) { 1 }

      it { is_expected.to eq 10 }

      it "抽選を 1 回引くこと" do
        subject
        expect(described_class).to have_received(:sample_purification_minutes).once
      end
    end

    context "3 ブロックのとき" do
      let(:blocks) { 3 }

      it { is_expected.to eq 30 }

      it "抽選を 3 回引くこと" do
        subject
        expect(described_class).to have_received(:sample_purification_minutes).exactly(3).times
      end
    end

    context "スタブなしで 2 ブロックのとき" do
      before { allow(described_class).to receive(:sample_purification_minutes).and_call_original }
      let(:blocks) { 2 }

      it "抽選 2 回分の合計になること" do
        is_expected.to be_between(16, 30)
      end
    end
  end

  # =========================================================
  # .minutes_until_next_purification
  # =========================================================
  describe ".minutes_until_next_purification" do
    subject { described_class.minutes_until_next_purification(total_minutes) }

    context "nil のとき" do
      let(:total_minutes) { nil }
      it { is_expected.to eq 30 }
    end

    context "累計 0 分のとき" do
      let(:total_minutes) { 0 }
      it { is_expected.to eq 30 }
    end

    context "累計 25 分のとき" do
      let(:total_minutes) { 25 }
      it { is_expected.to eq 5 }
    end

    context "累計 30 分（ちょうど付与された直後）のとき" do
      let(:total_minutes) { 30 }

      it "次のブロックまでの 30 分を返すこと" do
        is_expected.to eq 30
      end
    end

    context "累計 265 分のとき" do
      let(:total_minutes) { 265 }
      it { is_expected.to eq 5 }
    end
  end
```

- [x] **Step 2: テストが失敗することを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb -e ".purification_blocks" -e ".sample_purification_minutes_for" -e ".minutes_until_next_purification"`

Expected: FAIL。`NoMethodError: undefined method 'purification_blocks'`。

- [x] **Step 3: 純粋関数を実装する**

`app/models/activity_record.rb` の `PURIFICATION_TIME_TABLE` の定義の直前に、ブロックの粒度を定数として置く。

置き換え前:

```ruby
  # 付与分数の重み付きテーブル（合計 100）
  PURIFICATION_TIME_TABLE = [
```

置き換え後:

```ruby
  # 浄化タイマー付与の 1 ブロック（分）。この分数がたまるごとに抽選を 1 回引く。
  PURIFICATION_BLOCK_MINUTES = 30

  # 付与分数の重み付きテーブル（合計 100）
  PURIFICATION_TIME_TABLE = [
```

次に `sample_purification_minutes` の `end` の直後（`# 浄化タイマーの時間計算メソッド` のコメント行の手前）に、以下の 3 つのメソッドを挿入する。

```ruby
  # 累計分数から、消化済みのブロック数を求める。
  # 余りを翌日へ繰り越さない設計のため、付与済みブロック数は累計だけから導出できる。
  def self.purification_blocks(minutes)
    [ minutes.to_i, 0 ].max / PURIFICATION_BLOCK_MINUTES
  end

  # blocks 回の抽選を引いた合計分数。乱数を含むため呼ぶたびに結果が変わる。
  def self.sample_purification_minutes_for(blocks)
    return 0 if blocks <= 0

    blocks.times.sum { sample_purification_minutes }
  end

  # 次の付与までの残り分数（マイページ表示用）。累計 0 分でも 30 を返す。
  def self.minutes_until_next_purification(total_minutes)
    PURIFICATION_BLOCK_MINUTES - [ total_minutes.to_i, 0 ].max % PURIFICATION_BLOCK_MINUTES
  end
```

- [x] **Step 4: テストが通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/activity_record_spec.rb`

Expected: PASS（0 failures）。既存の `.calculate_purification_time` の describe もまだ通る。

- [x] **Step 5: RuboCop を通す**

Run: `docker compose exec web bin/rubocop app/models/activity_record.rb spec/models/activity_record_spec.rb`

Expected: no offenses。

- [x] **Step 6: コミット**

```bash
git add app/models/activity_record.rb spec/models/activity_record_spec.rb
git commit -m "$(cat <<'EOF'
feat: 浄化タイマーの付与計算を純粋関数に分解 #251

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 付与を1日の累計ベースに切り替える

**Files:**
- Modify: `app/services/purification_time_granter.rb`（全体を置き換え）
- Modify: `app/forms/activity_record_form.rb:42`（`create!` の戻り値を受ける）, `:68`（Granter の呼び出し）
- Modify: `app/models/activity_record.rb`（`calculate_purification_time` を削除）
- Test: `spec/services/purification_time_granter_spec.rb`（全面改訂）, `spec/models/activity_record_spec.rb`（`.calculate_purification_time` の describe を削除）, `spec/forms/activity_record_form_spec.rb`（describe を追加）

**Interfaces:**
- Consumes: Task 1 の `ActivityRecord.total_light_time_on(user, date)`、Task 2 の `ActivityRecord.purification_blocks(minutes)` と `ActivityRecord.sample_purification_minutes_for(blocks)`
- Produces: `PurificationTimeGranter#call(activity_record)` → `Integer`（付与した実分数。付与なしは 0）。**引数が分数から保存済みの `ActivityRecord` に変わる。** 戻り値の意味は据え置きで、`ActivityRecordForm#granted_purification_minutes` 経由でフラッシュに使われる

- [x] **Step 1: 失敗するテストを書く**

`spec/services/purification_time_granter_spec.rb` の**全体**を以下で置き換える。

```ruby
require "rails_helper"

RSpec.describe PurificationTimeGranter, type: :service do
  let(:user)        { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }

  subject(:granter) { described_class.new(user) }

  # 付与分数は乱数（重み付き抽選）なので、テストでは 1 ブロック 10 分に固定する
  before { allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10) }

  # Granter は保存済みのレコードを受け取る。started_at は ended_at から逆算する。
  def create_record(total_duration, ended_at: Time.current, started_at: nil)
    create(:activity_record,
           user:           user,
           light_time:     light_time,
           total_duration: total_duration,
           started_at:     started_at || (ended_at - total_duration.minutes),
           ended_at:       ended_at)
  end

  describe "#call" do
    context "PurificationTime が既に存在するとき" do
      let!(:purification_time) { create(:purification_time, user: user, remaining_time: 0) }

      context "当日累計が 30 分に満たないとき" do
        it "付与されず 0 を返すこと" do
          aggregate_failures do
            expect(granter.call(create_record(25))).to eq 0
            expect(purification_time.reload.remaining_time).to eq 0
          end
        end
      end

      context "25 分を 2 回記録したとき" do
        it "2 回目で 1 ブロック付与されること" do
          first  = granter.call(create_record(25))
          second = granter.call(create_record(25))

          aggregate_failures do
            expect(first).to eq 0
            expect(second).to eq 10
            expect(purification_time.reload.remaining_time).to eq 600
          end
        end
      end

      context "累計 50 分の状態で 90 分を記録したとき" do
        before do
          granter.call(create_record(25))
          granter.call(create_record(25))
        end

        it "累計 140 分となり 3 ブロック付与されること" do
          # floor(140/30) - floor(50/30) = 4 - 1 = 3 ブロック
          aggregate_failures do
            expect(granter.call(create_record(90))).to eq 30
            expect(purification_time.reload.remaining_time).to eq 600 + 1800
          end
        end
      end

      context "1 件で複数ブロックをまたぐとき" do
        it "またいだ数だけ抽選が引かれること" do
          granter.call(create_record(90))
          expect(ActivityRecord).to have_received(:sample_purification_minutes).exactly(3).times
        end
      end

      context "日付が変わったとき" do
        it "累計がリセットされ、前日の 25 分が持ち越されないこと" do
          travel_to(Time.zone.local(2026, 9, 8, 22, 0, 0)) do
            granter.call(create_record(25))
          end

          granted = travel_to(Time.zone.local(2026, 9, 9, 10, 0, 0)) do
            granter.call(create_record(25))
          end

          aggregate_failures do
            expect(granted).to eq 0
            expect(purification_time.reload.remaining_time).to eq 0
          end
        end
      end

      context "0 時をまたぐセッションのとき" do
        it "前日に余りがあってもセッション単体で 30 分ごとに付与されること" do
          travel_to(Time.zone.local(2026, 9, 8, 22, 0, 0)) do
            granter.call(create_record(25))  # 前日累計 25 分・付与 0
          end

          granted = travel_to(Time.zone.local(2026, 9, 9, 0, 20, 0)) do
            granter.call(
              create_record(30,
                            started_at: Time.zone.local(2026, 9, 8, 23, 45, 0),
                            ended_at:   Time.zone.local(2026, 9, 9, 0, 15, 0))
            )
          end

          expect(granted).to eq 10
        end
      end

      context "ended_at が NULL のとき" do
        it "created_at の日で累計されて付与されること" do
          record = create_record(30)
          record.update_column(:ended_at, nil)

          expect(granter.call(record.reload)).to eq 10
        end
      end
    end

    context "PurificationTime がまだ存在しないとき" do
      context "1 ブロック分たまったとき" do
        it "PurificationTime が新規作成されて 600 秒セットされること" do
          record = create_record(30)

          aggregate_failures do
            expect { granter.call(record) }.to change(PurificationTime, :count).by(1)
            expect(user.reload.purification_time.remaining_time).to eq 600
          end
        end
      end

      context "当日累計が 30 分に満たないとき" do
        it "PurificationTime は作成されず 0 を返すこと" do
          record = create_record(20)

          aggregate_failures do
            expect { granter.call(record) }.not_to change(PurificationTime, :count)
            expect(granter.call(record)).to eq 0
          end
        end
      end
    end
  end
end
```

- [x] **Step 2: テストが失敗することを確認する**

Run: `docker compose exec web bundle exec rspec spec/services/purification_time_granter_spec.rb`

Expected: FAIL。現行の `call(total_duration)` に `ActivityRecord` が渡るため、`ActivityRecord.calculate_purification_time` の中で `total_duration < 1` の比較が `ArgumentError` / `NoMethodError` になる。

- [x] **Step 3: Granter を累計ベースに書き換える**

`app/services/purification_time_granter.rb` の**全体**を以下で置き換える。

```ruby
# 活動記録の登録に伴う浄化タイマー時間の付与をまとめるサービス。
#
# 付与の単位は「その日の光の時間の累計 30 分ごとに 1 ブロック」。保存した活動記録を
# 含む当日累計と、それを含まない累計のブロック数の差を取ることで、その保存によって
# 新たに越えたぶんだけを付与する。余りを翌日へ繰り越さない設計のため、付与済みの
# ブロック数は累計から導出でき、専用のカラムを持たずに済んでいる。
#
# 付与分数は 30 分ブロックごとの重み付き抽選（乱数）で決まるため、計算は必ず 1 回だけ行う。
# 付与した分数を戻り値として返すため、フラッシュ表示など呼び出し側が「実際に付与した値」を
# そのまま利用でき、再計算による表示と保存のズレを防ぐ。
class PurificationTimeGranter
  def initialize(user)
    @user = user
  end

  # 保存済みの activity_record を受け取り、その日の累計に応じた浄化タイマー時間を
  # 付与して、付与した分数を返す。付与が発生しないときは 0 を返す。
  #
  # 当日累計の読み取りから加算までを with_lock の中で行う。読み取りをロックの外に置くと、
  # 2 件の活動記録が同時に保存されたときに両方が同じ累計を読み、同じブロックを二重に
  # 付与しうる。
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

  # 保存後の当日累計と保存前の当日累計の差分ブロック数。
  # total_after は create! の後に取るため activity_record 自身を含んでいる。
  def newly_earned_blocks(activity_record)
    total_after  = ActivityRecord.total_light_time_on(@user, activity_day(activity_record))
    total_before = total_after - activity_record.total_duration.to_i

    ActivityRecord.purification_blocks(total_after) - ActivityRecord.purification_blocks(total_before)
  end

  # 活動がどの日のものかは終了時刻で決める（ActivityRecord::ACTIVITY_AT と同じ規則）
  def activity_day(activity_record)
    (activity_record.ended_at || activity_record.created_at).in_time_zone.to_date
  end
end
```

- [x] **Step 4: Granter のテストが通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/services/purification_time_granter_spec.rb`

Expected: PASS（0 failures）。

- [x] **Step 5: フォームの呼び出しを変える**

`app/forms/activity_record_form.rb` の `create!` の戻り値を変数に受ける。

置き換え前:

```ruby
      # ActivityRecord 作成
      user.activity_records.create!(
```

置き換え後:

```ruby
      # ActivityRecord 作成
      activity_record = user.activity_records.create!(
```

続いて Granter の呼び出しを変える。

置き換え前:

```ruby
      # 浄化タイマーの付与（計算は乱数を含むためここで 1 回だけ実行し、実値を保持）
      @granted_purification_minutes = PurificationTimeGranter.new(user).call(total_duration)
```

置き換え後:

```ruby
      # 浄化タイマーの付与（当日累計から算出。乱数を含むためここで 1 回だけ実行し、実値を保持）
      @granted_purification_minutes = PurificationTimeGranter.new(user).call(activity_record)
```

- [x] **Step 6: フォームのテストを追加する**

`spec/forms/activity_record_form_spec.rb` の `describe "#save"` ブロックの末尾（`context "light_time_id が nil のとき"` の `end` の直後、`describe "#save"` を閉じる `end` の手前）に、以下を挿入する。

```ruby
    context "浄化タイマーの付与" do
      # 付与分数は乱数なので 1 ブロック 10 分に固定する
      before { allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10) }

      it "当日累計が 30 分に満たないときは付与されないこと" do
        form = described_class.new(valid_attributes.merge(total_duration: 25, idle_duration: 0))

        aggregate_failures do
          expect(form.save(user)).to be true
          expect(form.granted_purification_minutes).to eq 0
        end
      end

      it "25 分を 2 回保存すると 2 回目で付与されること" do
        first  = described_class.new(valid_attributes.merge(total_duration: 25, idle_duration: 0))
        second = described_class.new(valid_attributes.merge(total_duration: 25, idle_duration: 0))
        first.save(user)
        second.save(user)

        aggregate_failures do
          expect(first.granted_purification_minutes).to eq 0
          expect(second.granted_purification_minutes).to eq 10
          expect(user.reload.purification_time.remaining_time).to eq 600
        end
      end
    end
```

- [x] **Step 7: フォームのテストが通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/forms/activity_record_form_spec.rb`

Expected: PASS（0 failures）。

- [x] **Step 8: 使われなくなった `calculate_purification_time` を削除する**

呼び出し元が消えたので、`app/models/activity_record.rb` から以下のメソッドを丸ごと削除する。

```ruby
  # 浄化タイマーの時間計算メソッド（30分ブロックごとにランダム付与）
  def self.calculate_purification_time(total_duration)
    return 0 if total_duration.blank? || total_duration < 1

    blocks = (total_duration / 30).floor
    return 0 if blocks == 0

    blocks.times.sum { sample_purification_minutes }
  end
```

あわせて `spec/models/activity_record_spec.rb` の `describe ".calculate_purification_time" do ... end` を、その上の区切りコメント（`# =====` で挟まれた `# .calculate_purification_time` の 3 行）ごと丸ごと削除する。境界値の検証は Task 2 の `.purification_blocks` と `.sample_purification_minutes_for` が引き継いでいる。

- [x] **Step 9: 残っていないことを確認する**

Run: `docker compose exec web grep -rn "calculate_purification_time" app/ spec/ CLAUDE.md`

Expected: `CLAUDE.md` の 1 件のみがヒットする（Task 5 で更新する）。`app/` と `spec/` からは消えていること。

- [x] **Step 10: 全テストを回す**

Run: `docker compose exec web bundle exec rspec spec/models spec/services spec/forms spec/requests`

Expected: PASS（0 failures）。

- [x] **Step 11: RuboCop を通す**

Run: `docker compose exec web bin/rubocop app/models/activity_record.rb app/services/purification_time_granter.rb app/forms/activity_record_form.rb spec/models/activity_record_spec.rb spec/services/purification_time_granter_spec.rb spec/forms/activity_record_form_spec.rb`

Expected: no offenses。

- [x] **Step 12: コミット**

```bash
git add app/models/activity_record.rb app/services/purification_time_granter.rb app/forms/activity_record_form.rb spec/
git commit -m "$(cat <<'EOF'
feat: 浄化タイマーの付与を1日の累計時間ベースに変更 #251

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: マイページに次の付与までの残り分数を表示する

**Files:**
- Modify: `app/controllers/mypages_controller.rb:6`（`@today_light_time` の直後）
- Modify: `app/views/mypages/_pomodoro_start.html.erb:7-9`
- Modify: `app/views/static_pages/how_to_use/_step3.html.erb:18-20`（新しい表示の説明）
- Test: `spec/system/purification_times_spec.rb`

**Interfaces:**
- Consumes: Task 2 の `ActivityRecord.minutes_until_next_purification(total_minutes)`、Task 1 の `ActivityRecord.total_light_time_today(user)`
- Produces: インスタンス変数 `@minutes_to_next_purification`（`Integer`。1〜30）。`_pomodoro_start.html.erb` からのみ参照される

**注意:** `_pomodoro_start.html.erb` は `light_and_dark_times_present` が真のときだけ描画される（`app/views/mypages/show.html.erb:70-73`）。System Spec では `let!(:light_time)` と `let!(:dark_time)` が既にあるので条件を満たす。

- [x] **Step 1: 失敗するテストを書く**

`spec/system/purification_times_spec.rb` の `describe "マイページの浄化タイマー表示"` ブロックの直後（その `end` の次）に、以下の `describe` を挿入する。

```ruby
  # =========================================================
  # マイページの累計進捗表示
  # =========================================================
  describe "マイページの次の付与までの表示" do
    context "今日の記録がないとき" do
      it "あと 30 分と表示されること" do
        visit mypage_path
        expect(page).to have_content("次の浄化タイマーまで あと 30 分")
      end
    end

    context "今日 25 分の記録があるとき" do
      before do
        create(:activity_record, user: user, light_time: light_time,
                                 total_duration: 25, idle_duration: 0)
      end

      it "あと 5 分と表示されること" do
        visit mypage_path
        expect(page).to have_content("次の浄化タイマーまで あと 5 分")
      end
    end

    context "今日 30 分ちょうどの記録があるとき" do
      before do
        create(:activity_record, user: user, light_time: light_time,
                                 total_duration: 30, idle_duration: 0)
      end

      it "次のブロックまでの 30 分が表示されること" do
        visit mypage_path
        expect(page).to have_content("次の浄化タイマーまで あと 30 分")
      end
    end
  end
```

- [x] **Step 2: テストが失敗することを確認する**

Run: `docker compose exec web bundle exec rspec spec/system/purification_times_spec.rb -e "マイページの次の付与までの表示"`

Expected: FAIL（3 examples）。文言がまだ存在しない。

- [x] **Step 3: コントローラに残り分数を渡す**

`app/controllers/mypages_controller.rb` を編集する。

置き換え前:

```ruby
    @today_light_time = ActivityRecord.total_light_time_today(current_user)
```

置き換え後:

```ruby
    @today_light_time = ActivityRecord.total_light_time_today(current_user)
    @minutes_to_next_purification = ActivityRecord.minutes_until_next_purification(@today_light_time)
```

- [x] **Step 4: ビューと使い方ページに表示を足す**

まず `app/views/mypages/_pomodoro_start.html.erb` の 7〜9 行目を置き換える。「今日の光の時間」の下マージンを `mb-8` から `mb-2` に詰め、新しい行が `mb-8` を引き継ぐ。

置き換え前:

```erb
  <p class="text-white/90 text-3xl font-bold mb-8">
    <%= format_minutes_to_hm(@today_light_time) %>
  </p>
```

置き換え後:

```erb
  <p class="text-white/90 text-3xl font-bold mb-2">
    <%= format_minutes_to_hm(@today_light_time) %>
  </p>

  <p class="text-white/90 md:text-zinc-800 text-sm mb-8">
    次の浄化タイマーまで あと <%= @minutes_to_next_purification %> 分
  </p>
```

次に使い方ページで新しい表示に触れる。`app/views/static_pages/how_to_use/_step3.html.erb` の「※ 活動時間・休憩時間は…」の `<p>`（18〜20 行目）の直後に、以下の `<p>` を挿入する。

```erb
    <p class="mb-2 text-md">
      ※ スタートボタンの上に「今日の光の時間」と、次に浄化タイマーが付与されるまでの残り時間が表示されます。
    </p>
```

この文言を検証する spec は無い（`spec/system/static_pages_spec.rb` は使い方ページの本文を assert していない）ので、テストの追加・修正は不要。

- [x] **Step 5: 新しいテストが通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/system/purification_times_spec.rb -e "マイページの次の付与までの表示"`

Expected: PASS（3 examples）。

- [x] **Step 6: 既存の System Spec が落ちることを確認する**

Run: `docker compose exec web bundle exec rspec spec/system/purification_times_spec.rb`

Expected: FAIL が 1 件。`context "PurificationTime が存在しないとき(ActivityRecord 未登録)"` の `it "浄化タイマー UI が表示されないこと"`。

新しく足した文言「次の浄化タイマーまで あと 30 分」に**「浄化タイマー」という語が含まれる**ため、`expect(page).not_to have_content("浄化タイマー")` が引っかかる。このテストが本当に守りたいのは「**浄化タイマーのカードが描画されないこと**」（`app/views/mypages/show.html.erb:20` の `<% if @purification_time %>`）であり、文字列一致はその代理でしかなかった。カードを直接見る形に精密化する。

- [x] **Step 7: 既存テストの assertion を精密化する**

`spec/system/purification_times_spec.rb` の当該 `context` を置き換える。

置き換え前:

```ruby
    context "PurificationTime が存在しないとき(ActivityRecord 未登録)" do
      it "浄化タイマー UI が表示されないこと" do
        visit mypage_path
        expect(page).not_to have_content("浄化タイマー")
      end
    end
```

置き換え後:

```ruby
    context "PurificationTime が存在しないとき(ActivityRecord 未登録)" do
      # 「次の浄化タイマーまで あと○分」の進捗表示は常に出るため、文字列一致ではなく
      # カード（data-controller="purification-timer"）の有無で判定する
      it "浄化タイマーのカードが表示されないこと" do
        visit mypage_path
        aggregate_failures do
          expect(page).not_to have_css("[data-controller='purification-timer']", visible: :all)
          expect(page).not_to have_link("スタート", href: purification_time_path)
          expect(page).not_to have_link("メッセージ", href: purification_time_path)
        end
      end
    end
```

- [x] **Step 8: System Spec 全体が通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/system/purification_times_spec.rb`

Expected: PASS（0 failures）。

- [x] **Step 9: 他の System Spec に波及していないことを確認する**

Run: `docker compose exec web bundle exec rspec spec/system`

Expected: PASS（0 failures）。マイページを訪れる `activity_records_spec.rb` / `timer_exclusion_spec.rb` は「浄化タイマー」の文字列一致に依存していないが、念のため確認する。

- [x] **Step 10: RuboCop を通す**

Run: `docker compose exec web bin/rubocop app/controllers/mypages_controller.rb spec/system/purification_times_spec.rb`

Expected: no offenses。

- [x] **Step 11: コミット**

```bash
git add app/controllers/mypages_controller.rb app/views/mypages/_pomodoro_start.html.erb app/views/static_pages/how_to_use/_step3.html.erb spec/system/purification_times_spec.rb
git commit -m "$(cat <<'EOF'
feat: マイページに次の浄化タイマー付与までの残り分数を表示 #251

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: ドキュメントを更新して全体を検証する

**Files:**
- Modify: `README.md:117`
- Modify: `app/views/static_pages/how_to_use/_step4.html.erb:55`
- Modify: `CLAUDE.md`（「活動記録のフロー」節）

**Interfaces:**
- Consumes: Task 1〜4 で確定した仕様と API（`ACTIVITY_AT`、`purification_blocks`、`sample_purification_minutes_for`、`call(activity_record)`）
- Produces: なし（ドキュメントのみ）

- [x] **Step 1: README と使い方ページの付与ルールを更新する**

どちらもユーザーに付与ルールを説明している箇所なので、まとめて直す。

まず `README.md` の 117 行目を置き換える。

置き換え前:

```markdown
4. 活動記録を提出すると光の時間30分につき10分「浄化タイマー」が付与される。浄化タイマーを用いることで、罪悪感なく娯楽を楽しめる。
```

置き換え後:

```markdown
4. 活動記録を提出すると、その日の光の時間の累計30分ごとに「浄化タイマー」が付与される（付与分数は8〜15分のランダム）。累計は0時にリセットされ、30分に満たない余りは翌日へ繰り越されない。マイページで次の付与までの残り時間を確認できる。浄化タイマーを用いることで、罪悪感なく娯楽を楽しめる。
```

次に `app/views/static_pages/how_to_use/_step4.html.erb` の 55 行目を置き換える。現在の「30分毎に」は**何の 30 分かを書いていない**（暗黙に「そのセッションの」を指していた）ため、累計であることを明示する。

置き換え前:

```erb
    <p class="mb-2 text-md">※ デモ画像です。実際の付与時間は30分毎にランダムで付与されます（8分・10分・13分・15分のいずれか）。</p>
```

置き換え後:

```erb
    <p class="mb-2 text-md">※ デモ画像です。実際は、その日の光の時間の累計が30分たまるごとに、ランダムな時間（8分・10分・13分・15分のいずれか）が付与されます。</p>
    <p class="mb-2 text-md">※ 累計は0時にリセットされ、30分に満たない分は翌日へ繰り越されません。</p>
```

同ファイル 18 行目の「この値は登録後に付与される浄化タイマーには影響しません」（`idle_duration` の説明）は**変更しない**。付与は従来どおり `total_duration` ベースで、`idle_duration` は影響しないままである。

- [x] **Step 2: CLAUDE.md の「活動記録のフロー」節を更新する**

`CLAUDE.md` の該当箇所を置き換える。

置き換え前:

```markdown
- 浄化タイマーの付与分数の計算は `ActivityRecord.calculate_purification_time` のクラスメソッド（純粋関数）に残っています。`total_duration` の 30 分ブロックごとに `sample_purification_minutes`（`PURIFICATION_TIME_TABLE` の重み付き抽選）を引いて合計します。**乱数を含むため、同じ入力でも呼ぶたびに結果が変わります。表示・保存で複数回呼ばないこと。**

浄化タイマーへの「加算（副作用）」は `PurificationTimeGranter`（`app/services/`）に切り出してあります。`PurificationTimeGranter.new(user).call(total_duration)` が `user.with_lock` 内で `PurificationTime` に加算し、**付与した実分数を返します**。
```

置き換え後:

```markdown
- 浄化タイマーの付与は**1 セッション単位ではなく、その日の光の時間の累計 30 分ごと**です。計算は `ActivityRecord` のクラスメソッド（純粋関数）に分かれています。`purification_blocks(minutes)` が累計分数から消化済みブロック数（`floor(累計 / 30)`）を求め、`sample_purification_minutes_for(blocks)` がブロック数だけ `sample_purification_minutes`（`PURIFICATION_TIME_TABLE` の重み付き抽選）を引いて合計します。**後者は乱数を含むため、同じ入力でも呼ぶたびに結果が変わります。表示・保存で複数回呼ばないこと。**
- 余りを翌日へ繰り越さないため、**付与済みブロック数は当日累計から導出できます**。専用のカラムは持ちません。「その活動がどの日のものか」は `ActivityRecord::ACTIVITY_AT`（= `COALESCE(ended_at, created_at)`）に集約されており、`today` / `activity_on` / `within_last_days` / `daily_series` がすべてこの式を使います。`created_at` は記録の送信時刻なので日付の判定には使いません。

浄化タイマーへの「加算（副作用）」は `PurificationTimeGranter`（`app/services/`）に切り出してあります。`PurificationTimeGranter.new(user).call(activity_record)` が **保存済みの `ActivityRecord` を受け取り**、`user.with_lock` 内でその日の累計を読んで差分ブロック分を `PurificationTime` に加算し、**付与した実分数を返します**。累計の読み取りをロックの外に出すと同時保存で二重付与が起きるため、読み取りから加算までをロック内に閉じています。
```

- [x] **Step 3: 古い記述が残っていないことを確認する**

Run: `docker compose exec web grep -rn "calculate_purification_time\|call(total_duration)\|30分につき10分\|30分毎にランダム" app/ spec/ README.md CLAUDE.md`

Expected: ヒット 0 件。

- [x] **Step 4: 全テストを回す**

Run: `docker compose exec web bundle exec rspec`

Expected: PASS（0 failures）。

- [x] **Step 5: RuboCop を全体にかける**

Run: `docker compose exec web bin/rubocop`

Expected: no offenses。

- [x] **Step 6: セキュリティスキャンを通す**

Run: `docker compose exec web bin/brakeman --no-pager && docker compose exec web bin/bundler-audit check`

Expected: `No warnings found` / `No vulnerabilities found`。

Brakeman が `ACTIVITY_AT` の文字列補間で SQL injection を報告した場合は、Task 1 Step 10 の代替方針（定数化をやめて 3 箇所に SQL リテラルを直書き）に切り替え、Task 1〜3 のテストを回し直してから進む。

- [x] **Step 7: コミット**

```bash
git add README.md CLAUDE.md app/views/static_pages/how_to_use/_step4.html.erb
git commit -m "$(cat <<'EOF'
docs: 浄化タイマーの累計付与に合わせて README・使い方ページ・CLAUDE.md を更新 #251

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 8: コードレビューを受ける**

PR を作る前にコードレビューを通す。`superpowers:requesting-code-review` スキル、または `/code-review` を使う。

指摘があれば `superpowers:receiving-code-review` に従って対応し、修正後に Step 4〜6 を回し直す。

- [x] **Step 9: PR を作成する**

```bash
git push -u origin feat/daily-cumulative-purification-251
gh pr create --title "浄化タイマーの付与を1日の累計時間ベースに変更する" --body "$(cat <<'EOF'
## 概要

浄化タイマーの付与単位を「1 セッションの活動時間」から「1 日の累計活動時間」に変更した。25 分のセッションを 2 回こなしても付与 0 になる問題を解消する。

Closes #251

## 変更点

- その日の光の時間の累計が 30 分たまるごとに 1 ブロック付与。0 時にリセットし、余りは翌日へ繰り越さない
- 「その活動がどの日のものか」の判定を `created_at`（送信時刻）から `ended_at`（活動の終了時刻）へ変更。`ActivityRecord::ACTIVITY_AT` に集約し、`today` / `within_last_days` / `daily_series` を揃えた
- 0 時をまたぐセッションは終了した日に丸ごと計上されるため、そのセッション単体で 30 分ごとに付与される（またぎ専用の分岐は無し）
- `PurificationTimeGranter#call` の引数を分数から `ActivityRecord` に変更し、当日累計の読み取りを `with_lock` 内へ移して同時保存による二重付与を防いだ
- マイページに「次の浄化タイマーまで あと○分」を追加

## 設計書

`docs/superpowers/specs/2026-09-09-daily-cumulative-purification-design.md`

## 補足

- **マイグレーションなし。** 余りを繰り越さないため付与済みブロック数は累計から導出でき、カラムを追加していない
- **データ移行なし。** 旧 `Σ floor(セッション/30)` ≤ 新 `floor(Σ/30)` が常に成り立つため、二重付与は起きない
- 既知の制約として、活動記録を削除すると同じ時間で再度ブロックを獲得できる。動機が薄いため対策していない（設計書に記載）

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## スコープ外

- **使い方ページのスクリーンショット差し替え** — `how_to_use/mypage_light_time_create_multiple.png`（Step3）と `how_to_use/mypage_confirm_purification_time.png`（Step5）は、マイページに追加する「次の浄化タイマーまで あと○分」を含まない状態のまま残る。差し替えには手動キャプチャが必要なので本計画では対応しない。文章側で新しい表示に触れておく（Task 4 Step 4）。
  - `how_to_use/activity_record_granted_purification_time.png`（Step4 の付与フラッシュ）は**差し替え不要**。フラッシュの文言と見た目は変更しないため。
- **抽選テーブル `PURIFICATION_TIME_TABLE` の調整** — 累計制で付与機会が増えるぶん体感の獲得量は上がるが、まずは現行テーブルのまま様子を見る。
- **付与ロジックの `ActivityRecord` からの切り出し** — `PURIFICATION_TIME_TABLE` / `sample_purification_minutes` を含む浄化タイマー関連のクラスメソッド群は、本計画の完了時点で `ActivityRecord` に 6 つ並ぶ。専用の純粋オブジェクトへ移す価値はあるが、振る舞いの変更と構造の移動を同じ PR に混ぜると差分から「移動中に挙動が変わっていないか」を読み取れなくなるため、別 issue とする。
- **活動記録の削除による二度取りの防止** — 設計書の「既知の制約」のとおり対策しない。

## Self-Review

**1. Spec coverage**

| 設計書の節 | 実装タスク |
|---|---|
| 付与ルール（累計 30 分ごと、差分ブロック） | Task 2（`purification_blocks`）, Task 3（差分計算） |
| なぜカラムを追加しないのか | Task 3（累計からの導出。マイグレーション無し） |
| 基準日を `ended_at` に変える（4 対象） | Task 1 |
| `COALESCE` で包む理由 | Task 1（`ACTIVITY_AT`）、テストは Task 1 Step 1 の「ended_at が NULL のとき」 |
| 0 時またぎの扱い | Task 1（`total_light_time_on` のテスト）, Task 3（Granter のテスト） |
| 変更しないもの（抽選テーブル・粒度・タイミング・フラッシュ・トランザクション構成） | どのタスクでも触れない。Global Constraints に明記 |
| 実装: `ActivityRecord` | Task 1, Task 2 |
| 実装: `PurificationTimeGranter`（`with_lock` の範囲拡大を含む） | Task 3 |
| 実装: `ActivityRecordForm` | Task 3 Step 5 |
| 実装: マイページの進捗表示 | Task 4 |
| ドキュメント（README / CLAUDE.md） | Task 5 |
| 使い方ページの付与ルールの記述 | Task 5 Step 1（`_step4.html.erb`）, Task 4 Step 4（`_step3.html.erb`） |
| テスト（4 ファイル） | Task 1, 2, 3, 4 に分散 |
| 移行（データ移行不要） | 実装不要。PR 本文に記載 |
| 既知の制約（削除による二度取り） | 対策しない方針。PR 本文に記載 |
| 実装時に判断する点（Brakeman） | Task 1 Step 10, Task 5 Step 6 |

漏れなし。

**2. Placeholder scan**

「適切なエラーハンドリングを追加」「Task N と同様」「テストを書く（コード無し）」の類は無し。すべてのコードステップに実際のコードを記載済み。

**3. Type consistency**

| 名前 | 定義 | 参照 |
|---|---|---|
| `ActivityRecord::ACTIVITY_AT` | Task 1 Step 3 | Task 1 Step 3（`daily_series`）, Task 5 Step 2（CLAUDE.md） |
| `ActivityRecord.activity_on(date)` | Task 1 Step 3 | Task 1 Step 3（`today` / `total_light_time_on`） |
| `ActivityRecord.total_light_time_on(user, date)` | Task 1 Step 3 | Task 1 Step 1（テスト）, Task 3 Step 3（Granter） |
| `ActivityRecord::PURIFICATION_BLOCK_MINUTES` | Task 2 Step 3 | Task 2 Step 3（3 つの関数内） |
| `ActivityRecord.purification_blocks(minutes)` | Task 2 Step 3 | Task 3 Step 3（`newly_earned_blocks`） |
| `ActivityRecord.sample_purification_minutes_for(blocks)` | Task 2 Step 3 | Task 3 Step 3（`call`） |
| `ActivityRecord.minutes_until_next_purification(total)` | Task 2 Step 3 | Task 4 Step 3（コントローラ） |
| `PurificationTimeGranter#call(activity_record)` | Task 3 Step 3 | Task 3 Step 5（フォーム） |
| `@minutes_to_next_purification` | Task 4 Step 3 | Task 4 Step 4（ビュー） |

名前の揺れなし。引数・戻り値の型も一致。
