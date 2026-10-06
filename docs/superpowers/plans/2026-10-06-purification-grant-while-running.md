# 実行中の浄化タイマーへの付与が stop! で消える不具合の修正 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 浄化タイマーが `running` の間に付与された時間が、その後の `stop!` / `finish!` で失われないようにする。

**Architecture:** 付与を `PurificationTime#add_time(seconds)` に寄せ、`running` かどうかの判定をモデルに閉じ込める。計測中（`counting?`）なら `total_time` も同じだけ延ばして終了予定時刻を後ろへずらし、期限切れのまま `running` で残っているなら先に終了扱い（`idle`・残り 0）へ精算してから足す。`add_time` は属性の代入だけを行い、保存は `PurificationTimeGranter` が払い出し台帳と一緒に `with_lock` 内で 1 回だけ行う。

**Tech Stack:** Rails 8.1 / PostgreSQL / Hotwire / RSpec + FactoryBot

**Spec:** `docs/superpowers/specs/2026-10-06-purification-grant-while-running-design.md`（実装後に書き起こしたもの。設計の正本はこの設計書と issue #282）

**関連:** issue #282 / ブランチ `fix/purification-grant-while-running-282`

**進捗メモ（2026-10-06 時点）:** 計画・設計書より先に Task 1・Task 2 の実装とテストを済ませた（本来の順序ではない）。Review Focus のテストも追加し、全体のテスト 799 件 green・rubocop clean・Brakeman 警告 0 を確認済み。残りは Task 3 のコードレビューと PR。

## 承認済みの設計

| 付与時の状態 | 処理 |
|---|---|
| `running` かつ `counting?`（期限前） | `remaining_time` と `total_time` の両方に加算。期限（`started_at + total_time`）が後ろへずれる |
| `running` だが期限切れ（`counting?` が false） | `finish!` と同じ属性（`idle`・残り 0・`total_time` 0・`started_at` / `paused_at` nil）を代入してから `remaining_time` に加算 |
| `idle` / `paused` | 従来どおり `remaining_time` に加算するだけ |

- issue 原案の「`running` なら `total_time` にも足す」だけでは、issue の再現手順（期限切れのまま残ったタイマー）が直らない。延ばしても期限がまだ過去にあれば、`stop!` で 0 になるため。
- 期限切れを精算して `idle` にするので、付与後も `counting?` は false のまま。#265 の永久ロック対策（期限切れの `running` がポモドーロをブロックしない）を壊さない。
- 計測中は `remaining_time == total_time` を保つ。画面表示（`purification_timer_controller.js`）は `remaining_time - 経過秒`、サーバー（`stop!` / `counting?`）は `total_time` 基準で計算するので、両者が一致する。
- 範囲外: `ActivityRecordsController#create` に浄化タイマーのサーバー側ガードを足すこと。同一ブラウザ内は localStorage のリース（`activity_lock.js`）で防がれており、別端末・リース失効などの稀な経路しか残らない。本修正でその経路でも時間は失われなくなる。

## Global Constraints

- コメント・テスト名は**日本語**。
- 文字列は**ダブルクォート**（`spec/**/*` も対象、`.rubocop.yml`）。
- テストは **RSpec**。コマンドは `docker compose exec web` を前置する。
- `travel_to` / `freeze_time` はグローバルに include 済み。
- **`travel_to` を使う example では、基準時刻のレコードを `let!` で先に作る。** `let` は遅延評価なので、ブロック内で初めて参照されると `started_at` が移動後の時刻で作られ、経過時間・期限切れの検証が成り立たない（実装中に 2 件この理由で誤って失敗した）。
- **`PurificationTime#reset!` / `finish!` は払い出し台帳（`granted_blocks_date` / `granted_blocks_count`）に触れない。** `add_time` の精算も同様。
- `start!` / `stop!` / `reset!` を汎用 `update` に置き換えない。
- マイグレーションは書かない。

## Review Focus

1. **`running` だが `started_at` が nil の不正データへの付与** — 例外を出さず、期限切れと同じく精算されて `idle`・残り＝付与分になること（Task 1 Step 5a）。
2. **ちょうど期限の瞬間（`Time.current == started_at + total_time`）の付与** — `counting?` は false なので精算側に倒れ、残り＝付与分になること（Task 1 Step 5b）。
3. **`paused` 中に付与 → 再開 → 停止** — `start!` が付与後の `remaining_time` を `total_time` にコピーするので、付与分が残ること（Task 1 Step 5c）。
4. **期限切れタイマーへの付与でも払い出し台帳が更新されること** — 精算の代入が台帳を巻き戻さず、同じブロックを再付与しないこと（Task 2 Step 5a）。
5. **計測中のタイマーに付与した直後、画面表示とサーバーの残りが一致すること** — `remaining_time == total_time` が保存後も保たれること（Task 2 Step 5b）。

---

## File Structure

| ファイル | 役割 | 変更内容 |
|---|---|---|
| `app/models/purification_time.rb` | 浄化タイマーの状態遷移 | `add_time(seconds)` を追加。`finish!` の属性を private の `finished_attributes` に切り出し、精算と共有 |
| `app/services/purification_time_granter.rb` | 付与の副作用（ロック・台帳・保存） | `remaining_time += minutes * 60` を `add_time(minutes * 60)` に置き換え |
| `spec/models/purification_time_spec.rb` | モデルの単体テスト | `#add_time` の describe を追加 |
| `spec/services/purification_time_granter_spec.rb` | 付与サービスのテスト | 「浄化タイマーが running のとき」の context を追加（issue の 2 シナリオ） |

---

### Task 1: `PurificationTime#add_time`

**Files:**
- Modify: `app/models/purification_time.rb`
- Test: `spec/models/purification_time_spec.rb`（`#reset!` の describe の直前に挿入）

**Interfaces:**
- Consumes: 既存の `running?` / `counting?` / `finish!`
- Produces: `PurificationTime#add_time(seconds) -> Integer`（`seconds` は付与する秒数。属性を代入するだけで保存しない。戻り値は使わない）

- [x] **Step 1: 失敗するテストを書く**

```ruby
  # =========================================================
  # #add_time
  # =========================================================
  describe "#add_time" do
    context "idle のとき" do
      let(:purification_time) { create(:purification_time, :idle_with_time) }

      it "remaining_time に加算され、状態は変わらないこと" do
        purification_time.add_time(300)

        aggregate_failures do
          expect(purification_time.remaining_time).to eq 900
          expect(purification_time.total_time).to eq 0
          expect(purification_time).to be_idle
        end
      end
    end

    context "paused のとき" do
      let(:purification_time) { create(:purification_time, :paused) }

      it "remaining_time に加算され、状態は変わらないこと" do
        purification_time.add_time(300)

        aggregate_failures do
          expect(purification_time.remaining_time).to eq 600
          expect(purification_time.total_time).to eq 600
          expect(purification_time).to be_paused
        end
      end
    end

    context "保存について" do
      let(:purification_time) { create(:purification_time, :idle_with_time) }

      # 呼び出し側（PurificationTimeGranter）が台帳と一緒に 1 回で save! するため
      it "保存はしないこと" do
        purification_time.add_time(300)
        expect(purification_time.reload.remaining_time).to eq 600
      end
    end

    context "running かつ計測中のとき" do
      let!(:purification_time) { create(:purification_time, :running) }

      it "stop! したときに付与分が残り時間に反映されること" do
        travel_to(4.minutes.from_now) { purification_time.add_time(300) }
        purification_time.save!

        travel_to(6.minutes.from_now) { purification_time.stop! }

        # 600 + 300 - 360 = 540 秒
        expect(purification_time.reload.remaining_time).to be_within(2).of(540)
      end

      it "counting? の期限が付与分だけ延びること" do
        purification_time.add_time(300)

        aggregate_failures do
          travel_to(12.minutes.from_now) { expect(purification_time.counting?).to be true }
          travel_to(16.minutes.from_now) { expect(purification_time.counting?).to be false }
        end
      end

      # 画面表示（JS）は remaining_time - 経過秒、サーバーは total_time - 経過秒で計算するため
      it "remaining_time と total_time が等しいまま保たれること" do
        purification_time.add_time(300)
        expect(purification_time.remaining_time).to eq purification_time.total_time
      end
    end

    context "running のまま終了時刻を過ぎているとき" do
      let!(:purification_time) { create(:purification_time, :running) }

      it "精算されて idle になり、残り時間が付与分になること" do
        travel_to(60.minutes.from_now) { purification_time.add_time(600) }

        aggregate_failures do
          expect(purification_time).to be_idle
          expect(purification_time.remaining_time).to eq 600
          expect(purification_time.total_time).to eq 0
          expect(purification_time.started_at).to be_nil
        end
      end

      it "精算後もポモドーロをブロックしないこと（counting? が false）" do
        travel_to(60.minutes.from_now) do
          purification_time.add_time(600)
          expect(purification_time.counting?).to be false
        end
      end
    end
  end
```

- [x] **Step 2: 失敗を確認する**

Run: `docker compose exec web bundle exec rspec spec/models/purification_time_spec.rb`
Expected: `#add_time` の 8 件が `NoMethodError: undefined method 'add_time'` で FAIL（2026-10-06 確認済み）

- [x] **Step 3: 最小の実装を書く**

`reset!` の直前に追加:

```ruby
  # 浄化タイマーに時間を付与する。保存は呼び出し側（PurificationTimeGranter）が
  # 払い出し台帳と一緒に 1 回で行うので、ここでは属性の代入だけにとどめる。
  #
  # running 中の残り時間は remaining_time ではなく total_time - 経過秒 で計算される
  # （stop! / counting?）。remaining_time にだけ足すと次の stop! で付与分が消えるため、
  # 状態に応じて次のように扱う。
  #   - 計測中: total_time も同じだけ延ばし、終了予定時刻を後ろへずらす
  #   - 期限切れのまま running で残っている: 先に終了扱い（idle・残り 0）に精算してから足す。
  #     延ばしても期限がまだ過去にあれば結局 0 になるうえ、精算すれば counting? が
  #     false のままなのでポモドーロもブロックしない
  def add_time(seconds)
    if running?
      if counting?
        self.total_time += seconds
      else
        assign_attributes(finished_attributes)
      end
    end

    self.remaining_time += seconds
  end
```

private の `finish!` を次に置き換える:

```ruby
  def finish!
    update!(finished_attributes)
  end

  def finished_attributes
    {
      status: :idle,
      remaining_time: 0,
      total_time: 0,
      started_at: nil,
      paused_at: nil
    }
  end
```

- [x] **Step 4: 通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/purification_time_spec.rb`
Expected: PASS（2026-10-06 確認済み）

- [x] **Step 5: Review Focus のテストを追加する**

5a. `#add_time` の describe の末尾に context を追加:

```ruby
    context "running だが started_at が nil の不正データのとき" do
      let!(:purification_time) { create(:purification_time, :running, started_at: nil) }

      it "例外を出さず、精算されて残り時間が付与分になること" do
        purification_time.add_time(600)

        aggregate_failures do
          expect(purification_time).to be_idle
          expect(purification_time.remaining_time).to eq 600
        end
      end
    end
```

5b. `running のまま終了時刻を過ぎているとき` の context 内の末尾に追加。`travel_to` は秒未満を切り捨てるため、factory の `started_at`（`Time.current`、マイクロ秒付き）から期限を計算すると、期限のわずかに手前へ移動して計測中側に倒れてしまう。秒ちょうどの `started_at` を明示する:

```ruby
      it "ちょうど期限の瞬間に付与しても精算側に倒れること" do
        deadline = Time.zone.local(2026, 9, 9, 10, 10, 0)
        purification_time.update!(started_at: deadline - purification_time.total_time)

        travel_to(deadline) { purification_time.add_time(600) }

        aggregate_failures do
          expect(purification_time).to be_idle
          expect(purification_time.remaining_time).to eq 600
        end
      end
```

5c. `paused のとき` の context 内の末尾に追加:

```ruby
      it "付与後に再開して止めても付与分が残ること" do
        purification_time.add_time(300)
        purification_time.save!

        freeze_time do
          purification_time.start!
          travel 1.minute
          purification_time.stop!
        end

        # 300 + 300 - 60 = 540 秒
        expect(purification_time.reload.remaining_time).to eq 540
      end
```

- [x] **Step 6: 通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/models/purification_time_spec.rb`
Expected: PASS（実装済みのコードで通る想定。落ちた場合は設計の想定漏れなので、実装を直す前にユーザーへ報告する）

- [x] **Step 7: コミット**

Task 2 の実装とまとめて 1 コミットにする（コミットは「設計書」「実装計画」「実装」の 3 つに分ける方針）。Task 2 Step 7 を参照。

---

### Task 2: `PurificationTimeGranter` を `add_time` 経由にする

**Files:**
- Modify: `app/services/purification_time_granter.rb:35`
- Test: `spec/services/purification_time_granter_spec.rb`（`PurificationTime がまだ存在しないとき` の context の直前に挿入）

**Interfaces:**
- Consumes: `PurificationTime#add_time(seconds)`（Task 1）
- Produces: 変更なし（`PurificationTimeGranter#call(activity_record) -> Integer` 付与した分数）

- [x] **Step 1: 失敗するテストを書く**

```ruby
    # #282: running 中に remaining_time だけへ加算すると、stop! が total_time から
    # 残りを計算し直すため付与分が消えていた
    context "浄化タイマーが running のとき" do
      let!(:purification_time) do
        create(:purification_time, user: user,
                                   status: :running, remaining_time: 600, total_time: 600,
                                   started_at: Time.zone.local(2026, 9, 9, 10, 0, 0))
      end

      it "計測中に付与された分が stop! 後も残ること" do
        travel_to(Time.zone.local(2026, 9, 9, 10, 4, 0)) do
          granter.call(create_record(30))
        end

        travel_to(Time.zone.local(2026, 9, 9, 10, 6, 0)) do
          purification_time.reload.stop!
        end

        # 600 + 600 - 360 = 840 秒
        expect(purification_time.reload.remaining_time).to eq 840
      end

      it "期限切れのまま残ったタイマーに付与された分が stop! 後も残ること" do
        travel_to(Time.zone.local(2026, 9, 9, 11, 0, 0)) do
          granter.call(create_record(30))
        end

        travel_to(Time.zone.local(2026, 9, 9, 11, 5, 0)) do
          purification_time.reload.stop!
        end

        aggregate_failures do
          expect(purification_time.reload.remaining_time).to eq 600
          expect(purification_time).to be_idle
        end
      end
    end
```

- [x] **Step 2: 失敗を確認する**

Run: `docker compose exec web bundle exec rspec spec/services/purification_time_granter_spec.rb`
Expected: FAIL。計測中は `expected: 840 got: 240`、期限切れは `expected: 600 got: 0`（issue の不具合の再現。2026-10-06 確認済み）

- [x] **Step 3: 最小の実装を書く**

```ruby
      minutes = ActivityRecord.sample_purification_minutes_for(blocks)
      purification_time.add_time(minutes * 60)
      purification_time.granted_blocks_date = day
      purification_time.granted_blocks_count = granted + blocks
      purification_time.save!
```

- [x] **Step 4: 通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/services/purification_time_granter_spec.rb`
Expected: PASS（2026-10-06 確認済み）

- [x] **Step 5: Review Focus のテストを追加する**

`浄化タイマーが running のとき` の context 内の末尾に追加:

5a.
```ruby
      it "期限切れのタイマーに付与しても払い出し台帳が更新され、同じブロックを再付与しないこと" do
        travel_to(Time.zone.local(2026, 9, 9, 11, 0, 0)) do
          first  = granter.call(create_record(30))
          second = granter.call(create_record(1))

          aggregate_failures do
            expect(first).to eq 10
            expect(second).to eq 0
            expect(purification_time.reload.granted_blocks_for(Date.new(2026, 9, 9))).to eq 1
          end
        end
      end
```

5b.
```ruby
      it "計測中に付与した直後も remaining_time と total_time が等しいこと（画面表示とサーバーの残りが一致する）" do
        travel_to(Time.zone.local(2026, 9, 9, 10, 4, 0)) do
          granter.call(create_record(30))
        end

        purification_time.reload
        aggregate_failures do
          expect(purification_time.remaining_time).to eq 1200
          expect(purification_time.total_time).to eq 1200
          expect(purification_time).to be_running
        end
      end
```

- [x] **Step 6: 通ることを確認する**

Run: `docker compose exec web bundle exec rspec spec/services/purification_time_granter_spec.rb`
Expected: PASS

- [x] **Step 7: コミット**

Task 1・Task 2 で編集した実装とテストを 1 コミットにまとめる。設計書・計画書はそれぞれ別のコミットにする。

```bash
git add docs/superpowers/specs/2026-10-06-purification-grant-while-running-design.md
git commit -m "docs: 実行中の浄化タイマーへの付与が消える不具合の設計書を追加 #282"

git add docs/superpowers/plans/2026-10-06-purification-grant-while-running.md
git commit -m "docs: 実行中の浄化タイマーへの付与が消える不具合の実装計画を追加 #282"

git add app/models/purification_time.rb app/services/purification_time_granter.rb \
        spec/models/purification_time_spec.rb spec/services/purification_time_granter_spec.rb
git commit -m "fix: 実行中の浄化タイマーに付与された時間が stop! で消える不具合を修正 #282"
```

---

### Task 3: 全体検証・コードレビュー・PR

**Files:**
- Modify: なし（レビュー指摘があればその対象ファイル）

**Interfaces:**
- Consumes: Task 1・Task 2 のコミット
- Produces: PR（`Closes #282`）

- [x] **Step 1: 全体のテストと lint を流す**

Run: `docker compose exec web bundle exec rspec && docker compose exec web bin/rubocop && docker compose exec web bundle exec brakeman --no-pager`（`bin/brakeman` は最新版チェックで止まるため直接実行する）
Expected: `0 failures` / `no offenses detected` / Brakeman の警告 0（2026-10-06 確認済み: rspec 799 件 green・rubocop clean・Brakeman 警告 0）

- [ ] **Step 2: コードレビューを通す**

`superpowers:requesting-code-review` で、ブランチ全体の差分（`main...HEAD`）をレビューする。指摘は `superpowers:receiving-code-review` で根拠を確かめてから反映し、反映したら Step 1 を再実行する。

- [ ] **Step 3: push して PR を作る**

```bash
git push -u origin fix/purification-grant-while-running-282
gh pr create --title "fix: 実行中の浄化タイマーに付与された時間が stop! で消える #282" --body "$(cat <<'EOF'
## 概要
浄化タイマーが running の間に付与された時間が、次の stop! で消える不具合を修正します。

Closes #282

## 変更内容
- `PurificationTime#add_time(seconds)` を追加し、付与時の状態で扱いを分けた
  - 計測中: `total_time` も延ばして終了予定時刻を後ろへずらす
  - 期限切れのまま running: 先に精算（idle・残り 0）してから足す
  - idle / paused: 従来どおり
- `PurificationTimeGranter` を `add_time` 経由にした

## issue の原案との違い
「running なら total_time にも足す」だけでは、期限切れのまま残ったタイマー（issue の再現手順）で期限がまだ過去にあり、stop! で 0 になるため、期限切れは精算する方式にしました。精算後は counting? が false のままなので、#265 の永久ロック対策も維持されます。

## テスト
- issue の 2 シナリオ（計測中・期限切れ）を Granter の spec で再現し、修正前に失敗することを確認済み
- `bundle exec rspec` / `bin/rubocop` green

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
