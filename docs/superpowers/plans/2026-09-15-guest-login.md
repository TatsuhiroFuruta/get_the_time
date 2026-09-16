# ゲストログイン機能 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ポートフォリオの閲覧者が、アカウント登録なしにデモデータ入りで Get The Time の全機能を体験できるようにする。

**Architecture:** ゲストログインのボタンを押すたびに使い捨ての `User`（`guest: true`）をデモデータ一式とともに作成し、`sign_in` する。削除は定期ジョブではなく、次の訪問者がボタンを押したときに「1時間無操作のゲスト」を一括 `delete_all` するリクエスト駆動方式。ゲスト判定は `users.guest` の1カラムに集約し、UI の出し分けとサーバ側のガードの両方に使う。

**Tech Stack:** Ruby 3.3.6 / Rails 8.1.3.1 / PostgreSQL / Devise / Hotwire (Turbo) / Tailwind CSS v4 / RSpec + FactoryBot + Capybara

**Spec:** `docs/superpowers/specs/2026-09-15-guest-login-design.md`

## Global Constraints

- 対象 issue は **#285**。すべてのコミットメッセージ末尾に ` #285` を含める。
- UI 文字列・フラッシュメッセージ・コメント・バリデーションメッセージはすべて**日本語**で書く（`config/application.rb` の `config.i18n.default_locale = :ja`）。
- テストは **RSpec**（Minitest ではない）。`bin/ci` / `config/ci.rb` の `bin/rails test` 記述は無視する。
- `.rspec` は `spec_helper` のみを require するため、Rails が必要な spec の先頭に `require "rails_helper"` を書く。
- `config.infer_spec_type_from_file_location!` は**無効**。`RSpec.describe "...", type: :request` のように type を明示する。
- 文字列リテラルは**ダブルクォート**（`.rubocop.yml` が `spec/**/*` を含めて強制）。
- コマンドはすべて `docker compose exec web` 経由で実行する。
- `config.time_zone = "Tokyo"`。`Time.current` / `Date.current` は JST。
- `app/services` と `app/forms` は `config.autoload_paths` に追加済みなので、`require` は不要。
- 新規ファイルを追加したら `docker compose exec web bin/rubocop` が通ることを確認する。

---

### Task 1: ゲスト識別カラムの追加

**Files:**
- Create: `db/migrate/<timestamp>_add_guest_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `spec/factories/users.rb`
- Test: `spec/models/user_spec.rb`

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces:
  - `users.guest`（boolean, default false, null false）
  - `users.last_request_at`（datetime, nullable）
  - `User.guest` → `ActiveRecord::Relation`（`where(guest: true)`）
  - FactoryBot trait `:guest`（`create(:user, :guest)` でゲストを作れる）

- [ ] **Step 1: マイグレーションを生成する**

```bash
docker compose exec web bin/rails generate migration AddGuestToUsers
```

- [ ] **Step 2: マイグレーションの中身を書く**

生成された `db/migrate/<timestamp>_add_guest_to_users.rb` を次の内容にする。

```ruby
class AddGuestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :guest, :boolean, default: false, null: false
    add_column :users, :last_request_at, :datetime

    # 削除の絞り込みは「guest かつ last_request_at が古い」のみ。ゲスト行だけを
    # 索引する部分インデックスにして、実ユーザーが増えてもインデックスを小さく保つ。
    add_index :users, :last_request_at, where: "guest"
  end
end
```

- [ ] **Step 3: マイグレーションを実行する**

```bash
docker compose exec web bin/rails db:migrate
```

Expected: `db/schema.rb` の version が更新され、`users` テーブルに `guest` と `last_request_at`、`index_users_on_last_request_at` が現れる。

- [ ] **Step 4: 失敗するテストを書く**

`spec/models/user_spec.rb` の一番外側の `RSpec.describe User` ブロックの末尾（最後の `end` の直前）に追記する。

```ruby
  describe "ゲスト" do
    describe ".guest" do
      it "guest: true のユーザーだけを返すこと" do
        guest = create(:user, :guest)
        create(:user)

        expect(described_class.guest).to contain_exactly(guest)
      end
    end

    it "通常のユーザーは guest が false であること" do
      expect(create(:user).guest).to be false
    end

    it "ゲストは last_request_at を持つこと" do
      expect(create(:user, :guest).last_request_at).to be_present
    end
  end
```

- [ ] **Step 5: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/models/user_spec.rb -e "ゲスト"
```

Expected: FAIL。`:guest` trait が未定義のため `KeyError: Trait not registered: "guest"`。

- [ ] **Step 6: ファクトリに trait を足す**

`spec/factories/users.rb` を次の内容にする。

```ruby
FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }

    # ゲストユーザー。削除判定に使う last_request_at も必ず入れる。
    trait :guest do
      guest { true }
      name { "ゲストユーザー" }
      sequence(:email) { |n| "guest_#{n}@example.com" }
      last_request_at { Time.current }
    end
  end
end
```

- [ ] **Step 7: モデルに scope を足す**

`app/models/user.rb` の `after_create :create_pomodoro_setting` の直後に追記する。

```ruby
  # ゲストユーザーの絞り込み。削除対象の特定に使う。
  scope :guest, -> { where(guest: true) }
```

- [ ] **Step 8: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/models/user_spec.rb
```

Expected: PASS（既存の example も含めて全部）。

- [ ] **Step 9: 既存テストが壊れていないことを確認する**

```bash
docker compose exec web bundle exec rspec
```

Expected: PASS。

- [ ] **Step 10: コミット**

```bash
git add db/migrate db/schema.rb app/models/user.rb spec/factories/users.rb spec/models/user_spec.rb
git commit -m "feat: ゲスト識別用の guest / last_request_at カラムを追加 #285"
```

---

### Task 2: デモデータの定義

**Files:**
- Create: `app/services/guest_demo_data.rb`
- Test: `spec/services/guest_demo_data_spec.rb`

**Interfaces:**
- Consumes: なし
- Produces（すべて `module_function`。`GuestDemoData` は純粋なデータで、DB には触らない）:
  - `GuestDemoData.light_times` → `Array<Hash>`。キーは `:action` / `:characteristic` / `:desired_self`。**先頭の要素が current になる**
  - `GuestDemoData.dark_time` → `Hash`。キーは `:behavior` / `:characteristic` / `:unwanted_future`
  - `GuestDemoData.activity_records(now)` → `Array<Hash>`。キーは `:light_time_index` / `:started_at` / `:ended_at` / `:task` / `:comment` / `:total_duration` / `:idle_duration` / `:desired_self_percentage` / `:satisfaction` / `:progress` / `:quality` / `:focus` / `:fatigue`
  - `GuestDemoData.regret_records(now)` → `Array<Hash>`。キーは `:title` / `:content` / `:favorited` / `:created_at`
  - `GuestDemoData.regret_summary` → `Hash`。キーは `:content`
  - `GuestDemoData.purification_time` → `Hash`。キーは `:remaining_time` / `:total_time` / `:status`

- [ ] **Step 1: 失敗するテストを書く**

`spec/services/guest_demo_data_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe GuestDemoData, type: :service do
  let(:now) { Time.zone.parse("2026-09-15 10:00:00") }

  describe ".light_times" do
    it "2件以上あり、先頭が current 用であること" do
      expect(described_class.light_times.size).to be >= 2
    end

    it "action が全件埋まっていること（LightTime は presence バリデーションがある）" do
      expect(described_class.light_times).to all(include(:action))
    end
  end

  describe ".activity_records" do
    subject(:records) { described_class.activity_records(now) }

    it "30件以上あること" do
      expect(records.size).to be >= 30
    end

    # 今日の記録を入れると PurificationTimeGranter が floor(当日累計 / 30) 個の
    # ブロックを閲覧者に払い出してしまう。これは設計上の不変条件。
    it "すべて昨日以前の記録であること" do
      today = now.to_date

      expect(records.map { |r| r[:ended_at].to_date }).to all(be < today)
    end

    it "5段階評価がすべて 1..5 に収まっていること（insert_all でバリデーションを飛ばすため）" do
      %i[satisfaction progress quality focus fatigue].each do |field|
        expect(records.map { |r| r[field] }).to all(be_between(1, 5))
      end
    end

    it "idle_duration が total_duration 以下であること" do
      expect(records).to all(satisfy { |r| r[:idle_duration] <= r[:total_duration] })
    end

    it "desired_self_percentage が (total - idle) / total で埋まっていること" do
      expect(records).to all(satisfy { |r|
        r[:desired_self_percentage] == ((r[:total_duration] - r[:idle_duration]).to_f / r[:total_duration]).round(2)
      })
    end

    it "started_at が ended_at から total_duration 分だけ前であること" do
      expect(records).to all(satisfy { |r| r[:ended_at] - r[:started_at] == r[:total_duration] * 60 })
    end

    it "light_time_index が light_times の範囲に収まっていること" do
      max_index = described_class.light_times.size - 1

      expect(records.map { |r| r[:light_time_index] }).to all(be_between(0, max_index))
    end
  end

  describe ".regret_records" do
    subject(:records) { described_class.regret_records(now) }

    it "8件以上あること" do
      expect(records.size).to be >= 8
    end

    it "お気に入りが1件以上あること（お気に入りフィルタのデモ用）" do
      expect(records.count { |r| r[:favorited] }).to be >= 1
    end

    it "content が全件埋まっていること（RegretRecord は null: false）" do
      expect(records.map { |r| r[:content] }).to all(be_present)
    end
  end

  describe ".purification_time" do
    it "残時間があり idle であること（カードが表示され、すぐ開始できる状態）" do
      expect(described_class.purification_time).to include(remaining_time: be > 0, status: 0)
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/services/guest_demo_data_spec.rb
```

Expected: FAIL。`NameError: uninitialized constant GuestDemoData`。

- [ ] **Step 3: GuestDemoData を実装する**

`app/services/guest_demo_data.rb` を作成する。

```ruby
# ゲストログインで投入するデモデータの定義。
#
# 「何を入れるか（文言）」と「どう入れるか（投入処理）」を分けるため、GuestUserBuilder
# から切り離してここに置く。日付を「生成時刻から N 日前」の相対で組み立てる必要が
# あるため、静的な YAML ではなく Ruby で持つ。
#
# db/seeds.rb の Faker は使わない。Faker::Config.locale がアプリの :ja を拾うため
# 日本語にはなるが、「人口半額壊す。」のような無意味な文字列になる。閲覧者が読む
# 画面に出すものなので、文言は手書きする。
#
# 活動記録は必ず昨日以前にする。今日の記録を入れると、閲覧者が活動記録を1件作った
# 瞬間に PurificationTimeGranter が floor(当日累計 / 30) 個のブロックを払い出して
# しまう（付与数は「当日累計から求めたブロック数 - 払い出し済み」で決まるため）。
module GuestDemoData
  module_function

  # 先頭の要素が is_current になる（GuestUserBuilder が switch_current! で設定する）。
  def light_times
    [
      { action: "プログラミング学習", characteristic: "朝のうちは驚くほど集中が続く", desired_self: "毎日手を動かし続けられるエンジニア" },
      { action: "読書", characteristic: "寝る前だと数ページで眠くなってしまう", desired_self: "月に3冊は読み切れる自分" },
      { action: "英語学習", characteristic: "音読を挟むと頭に入りやすい", desired_self: "英語の技術記事を辞書なしで読める自分" }
    ]
  end

  def dark_time
    {
      behavior: "夕食のあと、少しだけのつもりでショート動画を開いてしまう",
      characteristic: "疲れている日ほど歯止めが効かなくなる",
      unwanted_future: "毎晩同じ後悔を繰り返したまま、何も積み上がらない自分"
    }
  end

  def purification_time
    # remaining_time は台帳（granted_blocks_*）とは独立した値で、実際のモデルでも
    # 残時間は日をまたいで持ち越される。10分入れておくと「昨日の残り」として自然で、
    # マイページに浄化タイマーのカードが出てすぐ開始できる。
    { remaining_time: 600, total_time: 0, status: 0 }
  end

  def regret_summary
    {
      content: "夕方から夜にかけて、疲れを感じたタイミングで動画や SNS に手が伸びる傾向が見られます。" \
               "とくに予定を決めずに休憩に入った日ほど、時間が長く伸びているようです。" \
               "休憩の前に終わりの時刻を決めておくと、切り替えがしやすくなるかもしれません。"
    }
  end

  # [日数前, 光の時間index, 終了時刻(時), 作業内容, ふりかえり, 合計分, サボり分, 満足, 進捗, 品質, 集中, 疲労]
  SESSIONS = [
    [  1, 0, 10, "Rails のフォームオブジェクトを実装", "テストから書いたら手戻りがなかった",          50,  5, 4, 4, 4, 4, 2 ],
    [  1, 0, 15, "N+1 クエリを bullet で洗い出す",     "原因はすぐ見つかったが修正に手間取った",      45, 10, 3, 3, 4, 3, 3 ],
    [  1, 1, 21, "『リーダブルコード』を読む",         "命名の章が今の自分に刺さった",                30,  0, 5, 4, 5, 5, 2 ],
    [  2, 0,  9, "RSpec のリクエストスペックを追加",   "境界値のケースを足せた",                      60,  5, 4, 4, 4, 4, 3 ],
    [  2, 2, 20, "英単語アプリで語彙を増やす",         "眠くて後半は流し読みになった",                25, 10, 2, 2, 3, 2, 4 ],
    [  3, 0, 11, "Turbo Frame の挙動を検証",           "Content missing の原因が理解できた",          55,  5, 5, 5, 4, 4, 2 ],
    [  3, 1, 22, "技術書の輪読メモをまとめる",         "アウトプットすると記憶に残る",                35,  5, 4, 4, 4, 4, 3 ],
    [  4, 0, 10, "Devise のカスタムコントローラを読む", "継承元を追いかけるのに時間がかかった",       50, 10, 3, 3, 3, 3, 3 ],
    [  4, 0, 16, "マイグレーションと index を見直す",  "部分インデックスを初めて使った",              40,  0, 5, 5, 5, 5, 2 ],
    [  5, 2, 19, "英語の技術記事を音読する",           "知らない単語が多く辞書が手放せなかった",      30,  5, 3, 3, 3, 4, 3 ],
    [  5, 0,  9, "Tailwind のレスポンシブ調整",        "スマホ幅での崩れをひと通り直せた",            45,  5, 4, 4, 4, 4, 3 ],
    [  6, 0, 14, "Ransack の許可リストを整理",         "セキュリティの考え方が腹落ちした",            40,  0, 5, 4, 5, 5, 2 ],
    [  7, 0, 10, "Stimulus コントローラを書き直す",    "責務を分けたら読みやすくなった",              60,  5, 5, 5, 5, 4, 3 ],
    [  7, 1, 15, "『達人プログラマー』を読む",         "耳の痛い話が多かった",                        30,  0, 4, 4, 4, 4, 2 ],
    [  7, 2, 21, "英文法の復習",                       "仮定法でつまずいた",                          25,  5, 3, 3, 3, 3, 4 ],
    [  8, 0,  9, "サービスオブジェクトに切り出す",     "コントローラがかなり痩せた",                  55,  5, 5, 5, 5, 5, 2 ],
    [  8, 0, 17, "CI の失敗原因を調べる",              "アセットビルドの順序が原因だった",            35, 10, 3, 4, 3, 3, 4 ],
    [  9, 1, 20, "設計本の付箋を読み返す",             "以前より理解できるようになっていた",          30,  0, 5, 4, 5, 5, 2 ],
    [  9, 0, 11, "エラーハンドリングを整理",           "rescue の範囲を狭められた",                   45,  5, 4, 4, 4, 4, 3 ],
    [ 10, 0, 10, "Solid Queue の仕組みを調べる",       "ポーリング間隔の意味が分かった",              50,  5, 4, 5, 4, 4, 3 ],
    [ 10, 2, 19, "英語でコミットメッセージを書く練習", "短い文でも案外迷う",                          20,  5, 3, 3, 3, 3, 3 ],
    [ 11, 0,  9, "ER 図を描き直す",                    "テーブルの責務がはっきりした",                40,  0, 5, 5, 5, 5, 2 ],
    [ 11, 1, 22, "小説を読む",                         "気分転換になった",                            25,  0, 4, 3, 4, 4, 2 ],
    [ 12, 0, 13, "N 件同時保存の排他制御を調べる",     "with_lock の使いどころが分かった",            55,  5, 5, 5, 5, 4, 3 ],
    [ 12, 0, 18, "リファクタリングの差分を見直す",     "コミットを分けておいてよかった",              30,  5, 4, 4, 4, 4, 3 ],
    [ 13, 2, 20, "リスニング教材を聞き流す",           "ながら聞きになってしまった",                  30, 15, 2, 2, 2, 2, 4 ],
    [ 13, 0, 10, "テストの重複を共通化",               "shared_examples を使ってみた",                45,  5, 4, 4, 4, 4, 3 ],
    [ 14, 0,  9, "ポートフォリオの README を書く",     "人に読ませる文章は難しい",                    60, 10, 4, 4, 4, 3, 3 ],
    [ 14, 1, 15, "設計の本を読み進める",               "手を動かしながら読むと理解が早い",            35,  0, 5, 5, 5, 5, 2 ],
    [ 14, 0, 21, "ログイン周りの導線を見直す",         "実際に触ってみて気づくことが多い",            40,  5, 4, 4, 4, 4, 3 ]
  ].freeze

  def activity_records(now)
    SESSIONS.map do |days_ago, light_time_index, end_hour, task, comment, total, idle, satisfaction, progress, quality, focus, fatigue|
      # beginning_of_day を起点にするので、days_ago >= 1 なら必ず昨日以前に収まる。
      ended_at = (now - days_ago.days).beginning_of_day + end_hour.hours

      {
        light_time_index: light_time_index,
        started_at: ended_at - total.minutes,
        ended_at: ended_at,
        task: task,
        comment: comment,
        total_duration: total,
        idle_duration: idle,
        # insert_all! は before_save :calculate_desired_self_percentage を飛ばすため自分で入れる。
        desired_self_percentage: ((total - idle).to_f / total).round(2),
        satisfaction: satisfaction,
        progress: progress,
        quality: quality,
        focus: focus,
        fatigue: fatigue
      }
    end
  end

  # [日数前, お気に入りか, タイトル, 本文]
  REGRETS = [
    [  2, true,  "気づいたら日付が変わっていた",     "夕食のあと10分だけのつもりでショート動画を開いたら、気づけば2時間が経っていた。翌朝に回した勉強は結局できなかった。" ],
    [  3, false, "休憩の終わりを決めていなかった",   "区切りがいいところで休もうと思っていたのに、区切りを決めていなかったので延々と続けてしまった。" ],
    [  5, true,  "通知を切らずに始めてしまった",     "作業を始める前に通知を切るつもりが忘れていて、SNS の通知が来るたびに手が止まった。集中が戻るまでに毎回10分かかっていた気がする。" ],
    [  6, false, "疲れているときほど流される",       "残業で疲れた日は、何も考えずに動画を開いてしまう。疲れている日用の過ごし方を決めておきたい。" ],
    [  8, false, "寝る前にスマホを持ち込んだ",       "ベッドにスマホを持ち込んだ日は、決まって寝るのが1時間以上遅くなる。翌日の集中にも響いている。" ],
    [  9, true,  "やることを決めずに机に向かった",   "何をやるか決めないまま座ったので、結局ネットサーフィンで時間が溶けた。前日に決めておけばよかった。" ],
    [ 11, false, "週末に予定を入れすぎた",           "予定を詰め込んだ反動で、日曜の夜は何もする気が起きずダラダラしてしまった。" ],
    [ 12, false, "少しだけのつもりがゲームに",       "インストールし直したゲームを少しだけ触るつもりが、気づけば深夜になっていた。" ],
    [ 14, false, "調べもののつもりが脱線した",       "エラーの調査で検索していたはずが、関係のない記事を読み続けていた。調べる内容を書き出してから始めたい。" ]
  ].freeze

  def regret_records(now)
    REGRETS.map do |days_ago, favorited, title, content|
      created_at = (now - days_ago.days).beginning_of_day + 22.hours

      { title: title, content: content, favorited: favorited, created_at: created_at }
    end
  end
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/services/guest_demo_data_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 5: RuboCop を通す**

```bash
docker compose exec web bin/rubocop app/services/guest_demo_data.rb spec/services/guest_demo_data_spec.rb
```

Expected: no offenses。指摘が出たら `bin/rubocop -a` で修正する。

- [ ] **Step 6: コミット**

```bash
git add app/services/guest_demo_data.rb spec/services/guest_demo_data_spec.rb
git commit -m "feat: ゲスト用デモデータの定義を追加 #285"
```

---

### Task 3: ゲストユーザーの生成

**Files:**
- Create: `app/services/guest_user_builder.rb`
- Test: `spec/services/guest_user_builder_spec.rb`

**Interfaces:**
- Consumes: `GuestDemoData.light_times` / `.dark_time` / `.activity_records(now)` / `.regret_records(now)` / `.regret_summary` / `.purification_time`（Task 2）、`User.guest` scope と `users.guest` / `users.last_request_at`（Task 1）
- Produces: `GuestUserBuilder.call` → 保存済みの `User`（`guest: true`、デモデータ投入済み）

- [ ] **Step 1: 失敗するテストを書く**

`spec/services/guest_user_builder_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe GuestUserBuilder, type: :service do
  subject(:user) { described_class.call }

  describe ".call" do
    it "ゲストユーザーを返すこと" do
      expect(user).to be_guest
    end

    it "last_request_at が入っていること（nil だと削除条件に永久にマッチしない）" do
      expect(user.last_request_at).to be_present
    end

    it "メールアドレスが guest_ で始まること" do
      expect(user.email).to match(/\Aguest_[0-9a-f]{16}@example\.com\z/)
    end

    it "呼ぶたびに別のユーザーが作られること" do
      expect { described_class.call }.to change(User.guest, :count).by(1)
    end

    it "ポモドーロ設定が作られること（after_create コールバック）" do
      expect(user.pomodoro_setting).to be_present
    end

    it "闇の時間が作られること" do
      expect(user.dark_time).to be_present
    end

    it "光の時間が作られ、current がちょうど1件であること" do
      aggregate_failures do
        expect(user.light_times.count).to eq GuestDemoData.light_times.size
        expect(user.light_times.where(is_current: true).count).to eq 1
      end
    end

    it "マイページの中核 UI が出る状態になっていること" do
      expect(user.light_and_dark_times_present?).to be true
    end

    it "活動記録が投入されること" do
      expect(user.activity_records.count).to eq GuestDemoData::SESSIONS.size
    end

    it "活動記録の desired_self_percentage が埋まっていること" do
      expect(user.activity_records.where(desired_self_percentage: nil)).to be_empty
    end

    it "後悔記録と要約が投入されること" do
      aggregate_failures do
        expect(user.regret_records.count).to eq GuestDemoData::REGRETS.size
        expect(user.regret_summary).to be_present
      end
    end

    it "浄化タイマーに残時間があること" do
      expect(user.purification_time.remaining_time).to be > 0
    end

    # ここが設計上いちばん重要な不変条件。デモデータの日付を変えたときに
    # 静かに壊れるのを防ぐ。
    describe "浄化タイマーの不当付与が起きないこと" do
      it "今日の活動記録が0件であること" do
        expect(ActivityRecord.total_light_time_today(user)).to eq 0
      end

      it "払い出し済みブロックが0であること" do
        expect(user.purification_time.granted_blocks_for(Date.current)).to eq 0
      end

      it "閲覧者が30分の記録を1件作ったとき、付与は1ブロック分だけであること" do
        allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10)
        record = user.activity_records.create!(
          light_time: user.light_times.find_by(is_current: true),
          started_at: 30.minutes.ago,
          ended_at: Time.current,
          total_duration: 30,
          idle_duration: 0,
          satisfaction: 3, progress: 3, quality: 3, focus: 3, fatigue: 3
        )

        expect(PurificationTimeGranter.new(user).call(record)).to eq 10
      end
    end

    it "失敗したときに中途半端なユーザーを残さないこと" do
      allow(RegretRecord).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid)

      expect {
        begin
          described_class.call
        rescue ActiveRecord::StatementInvalid
          nil
        end
      }.not_to change(User, :count)
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/services/guest_user_builder_spec.rb
```

Expected: FAIL。`NameError: uninitialized constant GuestUserBuilder`。

- [ ] **Step 3: GuestUserBuilder を実装する**

`app/services/guest_user_builder.rb` を作成する。

```ruby
# ゲストユーザーとデモデータ一式を単一トランザクションで作るサービス。
#
# 関連データは insert_all! でまとめて入れる。1件ずつ create! すると活動記録だけで
# 30往復になり、ネットワーク越しの Neon ではログインの待ち時間に直結する
# （往復20msなら約0.6秒）。insert_all! なら生成全体が約10クエリに収まる。
#
# insert_all! はバリデーションもコールバックも飛ばすため、5段階評価・idle_duration・
# desired_self_percentage は GuestDemoData 側で担保している。
class GuestUserBuilder
  def self.call
    new.call
  end

  def call
    User.transaction do
      user = create_user
      light_time_ids = create_light_times(user)
      user.create_dark_time!(GuestDemoData.dark_time)
      insert_activity_records(user, light_time_ids)
      insert_regret_records(user)
      user.create_regret_summary!(GuestDemoData.regret_summary.merge(generated_at: Time.current))
      user.create_purification_time!(GuestDemoData.purification_time)
      user
    end
  end

  private

  def create_user
    # last_request_at を必ず入れる。nil のままだと削除条件 last_request_at < ? に
    # 永久にマッチせず、そのゲストが一度も削除されない。
    User.create!(
      guest: true,
      email: "guest_#{SecureRandom.hex(8)}@example.com",
      password: SecureRandom.hex(16),
      name: "ゲストユーザー",
      last_request_at: Time.current
    )
  end

  # current の設定は LightTime.switch_current! に通す。「ちょうど1件 current」の
  # 不変条件をこのメソッドが担保しているため、is_current を直接書かない。
  def create_light_times(user)
    light_times = GuestDemoData.light_times.map { |attrs| user.light_times.create!(attrs) }
    LightTime.switch_current!(user, light_times.first)

    light_times.map(&:id)
  end

  def insert_activity_records(user, light_time_ids)
    now = Time.current
    rows = GuestDemoData.activity_records(now).map do |attrs|
      attrs = attrs.dup
      light_time_id = light_time_ids.fetch(attrs.delete(:light_time_index))

      attrs.merge(user_id: user.id, light_time_id: light_time_id, created_at: now, updated_at: now)
    end

    ActivityRecord.insert_all!(rows)
  end

  def insert_regret_records(user)
    now = Time.current
    rows = GuestDemoData.regret_records(now).map do |attrs|
      attrs.merge(user_id: user.id, updated_at: now)
    end

    RegretRecord.insert_all!(rows)
  end
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/services/guest_user_builder_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 5: RuboCop を通す**

```bash
docker compose exec web bin/rubocop app/services/guest_user_builder.rb spec/services/guest_user_builder_spec.rb
```

Expected: no offenses。

- [ ] **Step 6: コミット**

```bash
git add app/services/guest_user_builder.rb spec/services/guest_user_builder_spec.rb
git commit -m "feat: デモデータ入りのゲストユーザーを生成するサービスを追加 #285"
```

---

### Task 4: ゲストユーザーの削除

**Files:**
- Create: `app/services/guest_user_purger.rb`
- Test: `spec/services/guest_user_purger_spec.rb`

**Interfaces:**
- Consumes: `User.guest` scope と `users.last_request_at`（Task 1）
- Produces: `GuestUserPurger.call(except_id: nil)` → 削除した件数（`Integer`）

- [ ] **Step 1: 失敗するテストを書く**

`spec/services/guest_user_purger_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe GuestUserPurger, type: :service do
  # 無操作時間を明示的に作るため時刻を固定する
  around { |example| freeze_time { example.run } }

  def guest(last_request_at:)
    create(:user, :guest, last_request_at: last_request_at)
  end

  describe ".call" do
    it "1時間以上無操作のゲストを削除すること" do
      stale = guest(last_request_at: 61.minutes.ago)

      expect { described_class.call }.to change { User.exists?(stale.id) }.from(true).to(false)
    end

    it "1時間未満のゲストは残すこと" do
      fresh = guest(last_request_at: 59.minutes.ago)

      described_class.call

      expect(User.exists?(fresh.id)).to be true
    end

    it "実ユーザーは last_request_at が nil でも削除しないこと" do
      real = create(:user)

      described_class.call

      expect(User.exists?(real.id)).to be true
    end

    it "except_id に指定したゲストは削除しないこと" do
      mine = guest(last_request_at: 2.hours.ago)

      described_class.call(except_id: mine.id)

      expect(User.exists?(mine.id)).to be true
    end

    it "except_id が nil でも動くこと" do
      guest(last_request_at: 2.hours.ago)

      expect { described_class.call(except_id: nil) }.to change(User.guest, :count).by(-1)
    end

    it "削除した件数を返すこと" do
      2.times { guest(last_request_at: 2.hours.ago) }

      expect(described_class.call).to eq 2
    end

    it "関連データも一緒に消えること" do
      stale = GuestUserBuilder.call
      stale.update_column(:last_request_at, 2.hours.ago)

      described_class.call

      aggregate_failures do
        expect(ActivityRecord.where(user_id: stale.id)).to be_empty
        expect(RegretRecord.where(user_id: stale.id)).to be_empty
        expect(RegretSummary.where(user_id: stale.id)).to be_empty
        expect(PurificationTime.where(user_id: stale.id)).to be_empty
        expect(LightTime.where(user_id: stale.id)).to be_empty
        expect(DarkTime.where(user_id: stale.id)).to be_empty
        expect(PomodoroSetting.where(user_id: stale.id)).to be_empty
        expect(User.where(id: stale.id)).to be_empty
      end
    end

    it "1回の実行で削除する件数に上限があること" do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      2.times { guest(last_request_at: 2.hours.ago) }

      expect(described_class.call).to eq 1
    end

    it "削除対象がないとき 0 を返すこと" do
      expect(described_class.call).to eq 0
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/services/guest_user_purger_spec.rb
```

Expected: FAIL。`NameError: uninitialized constant GuestUserPurger`。

- [ ] **Step 3: GuestUserPurger を実装する**

`app/services/guest_user_purger.rb` を作成する。

```ruby
# 使い終わったゲストユーザーとその関連データを削除するサービス。
#
# dependent: :destroy を使わず関連テーブルを一括 delete_all する。User#destroy は
# 関連を1行ずつ DELETE するため1ユーザーあたり約74クエリになり、ネットワーク越しの
# Neon では往復回数がそのまま実行時間になる。一括削除なら件数によらず8クエリで済む。
#
# 削除対象テーブルの一覧をここにも持つことになるが、7テーブルすべてに
# add_foreign_key が張られているため、User に関連を追加してここを更新し忘れれば
# User の DELETE が外部キー違反で失敗する。静かに孤児が残ることはない。
class GuestUserPurger
  # 無操作がこの時間を超えたゲストを削除対象にする。
  #
  # last_request_at は ApplicationController で10分間引きして更新するため、最大10分
  # 古い値になりうる。したがって実際に削除されるのは「50〜60分の無操作」であり、
  # 席を外した閲覧者を消してしまう事故が起きにくい。
  INACTIVE_FOR = 1.hour

  # 1回の実行で削除する上限。想定外に溜まったときの実行時間を頭打ちにする。
  # 残りは次の訪問者が来たときに持ち越される。
  BATCH_SIZE = 500

  def self.call(except_id: nil)
    new(except_id: except_id).call
  end

  def initialize(except_id: nil)
    @except_id = except_id
  end

  # 削除した件数を返す。
  def call
    ids = target_ids
    return 0 if ids.empty?

    ActivityRecord.where(user_id: ids).delete_all
    RegretRecord.where(user_id: ids).delete_all
    RegretSummary.where(user_id: ids).delete_all
    PurificationTime.where(user_id: ids).delete_all
    LightTime.where(user_id: ids).delete_all
    DarkTime.where(user_id: ids).delete_all
    PomodoroSetting.where(user_id: ids).delete_all
    User.where(id: ids).delete_all
  end

  private

  attr_reader :except_id

  def target_ids
    scope = User.guest.where(last_request_at: ...INACTIVE_FOR.ago).limit(BATCH_SIZE)
    # except_id が nil のとき where.not(id: nil) は「id IS NOT NULL」になり意図が
    # 読めなくなるため、値があるときだけ条件を足す。
    scope = scope.where.not(id: except_id) if except_id

    scope.pluck(:id)
  end
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/services/guest_user_purger_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 5: RuboCop を通す**

```bash
docker compose exec web bin/rubocop app/services/guest_user_purger.rb spec/services/guest_user_purger_spec.rb
```

Expected: no offenses。

- [ ] **Step 6: コミット**

```bash
git add app/services/guest_user_purger.rb spec/services/guest_user_purger_spec.rb
git commit -m "feat: 無操作のゲストを一括削除するサービスを追加 #285"
```

---

### Task 5: 最終アクセス時刻の更新

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Test: `spec/requests/guest_activity_spec.rb`

**Interfaces:**
- Consumes: `users.last_request_at`（Task 1）
- Produces: `ApplicationController#touch_guest_activity`（`before_action`。ゲストのリクエストで `last_request_at` を10分間引きで更新する）

- [ ] **Step 1: 失敗するテストを書く**

`spec/requests/guest_activity_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe "ゲストの最終アクセス時刻", type: :request do
  around { |example| freeze_time { example.run } }

  context "ゲストのとき" do
    let(:guest) { create(:user, :guest, last_request_at: 11.minutes.ago) }

    before { sign_in guest }

    it "最終更新から10分以上経っていれば更新すること" do
      expect { get mypage_path }.to change { guest.reload.last_request_at }.to(Time.current)
    end

    it "最終更新から10分未満なら更新しないこと" do
      guest.update_column(:last_request_at, 9.minutes.ago)

      expect { get mypage_path }.not_to change { guest.reload.last_request_at }
    end

    it "updated_at を動かさないこと（update_column を使うため）" do
      expect { get mypage_path }.not_to change { guest.reload.updated_at }
    end
  end

  context "実ユーザーのとき" do
    let(:user) { create(:user) }

    before { sign_in user }

    it "last_request_at を更新しないこと（削除対象ではないため読まれない）" do
      get mypage_path

      expect(user.reload.last_request_at).to be_nil
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_activity_spec.rb
```

Expected: FAIL。1件目が `expected ... to have changed` で落ちる（`last_request_at` が更新されない）。

- [ ] **Step 3: ApplicationController に before_action を足す**

`app/controllers/application_controller.rb` の `before_action :configure_permitted_parameters, if: :devise_controller?` の直後に1行足す。

```ruby
  before_action :touch_guest_activity
```

そして `private` セクションの `def redirect_to_not_found` の直前に次のメソッドを足す。

```ruby
  # ゲストの最終アクセス時刻を記録する。GuestUserPurger の削除判定にのみ使うため、
  # 削除対象ではない実ユーザーでは更新しない（読まれない値のために毎リクエスト
  # UPDATE を走らせないため）。
  #
  # 毎回書くと Neon への書き込みが増えるので10分に1回までに間引く。この間引き幅の
  # ぶんだけ値が古くなりうるので、削除の猶予（1時間）はそれを見込んで設定している。
  #
  # updated_at を動かさず、バリデーションもコールバックも走らせないため update_column を使う。
  def touch_guest_activity
    return unless current_user&.guest?
    return if current_user.last_request_at&.after?(10.minutes.ago)

    current_user.update_column(:last_request_at, Time.current)
  end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_activity_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 5: 既存テストが壊れていないことを確認する**

```bash
docker compose exec web bundle exec rspec
```

Expected: PASS。`before_action` を全体に追加したため、ここで必ず全体を回す。

- [ ] **Step 6: コミット**

```bash
git add app/controllers/application_controller.rb spec/requests/guest_activity_spec.rb
git commit -m "feat: ゲストの最終アクセス時刻を10分間引きで記録する #285"
```

---

### Task 6: ゲストログインの入口

**Files:**
- Create: `app/controllers/users/guest_sessions_controller.rb`
- Modify: `config/routes.rb`
- Modify: `config/locales/views/ja.yml`
- Test: `spec/requests/users/guest_sessions_spec.rb`

**Interfaces:**
- Consumes: `GuestUserBuilder.call`（Task 3）、`GuestUserPurger.call(except_id:)`（Task 4）
- Produces:
  - ルート `POST /guest_sign_in` → `guest_sign_in_path`
  - `Users::GuestSessionsController#create`
  - セッションキー `session[:guest_sign_in]`（Task 11 が時間切れ判定に使う）
  - i18n キー `users.guest_sessions.flash_message.signed_in` / `.rate_limited`

- [ ] **Step 1: 失敗するテストを書く**

`spec/requests/users/guest_sessions_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe "Users::GuestSessions", type: :request do
  describe "POST /guest_sign_in" do
    it "ゲストを作成してマイページへ遷移すること" do
      expect { post guest_sign_in_path }.to change(User.guest, :count).by(1)

      expect(response).to redirect_to(mypage_path)
    end

    it "ログイン状態になること" do
      post guest_sign_in_path
      follow_redirect!

      expect(response).to have_http_status(:ok)
    end

    it "デモデータが投入されていること" do
      post guest_sign_in_path
      guest = User.guest.last

      aggregate_failures do
        expect(guest.light_and_dark_times_present?).to be true
        expect(guest.activity_records).not_to be_empty
        expect(guest.regret_summary).to be_present
      end
    end

    it "成功メッセージを出すこと" do
      post guest_sign_in_path

      expect(flash[:notice]).to eq I18n.t("users.guest_sessions.flash_message.signed_in")
    end

    it "無操作のゲストを掃除すること" do
      stale = create(:user, :guest, last_request_at: 2.hours.ago)

      post guest_sign_in_path

      expect(User.exists?(stale.id)).to be false
    end

    it "掃除が失敗してもログインは通すこと" do
      allow(GuestUserPurger).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { post guest_sign_in_path }.to change(User.guest, :count).by(1)

      expect(response).to redirect_to(mypage_path)
    end

    it "レート制限を超えたらトップページへ戻すこと" do
      # test 環境の cache_store は :null_store で increment が nil を返すため、
      # 回数超過を再現するには increment の戻り値を差し替える。
      # rate_limit は store をクラス定義時に束縛するので、その同じオブジェクトを差し替える。
      # これで効かない場合は
      #   allow_any_instance_of(ActiveSupport::Cache::NullStore).to receive(:increment).and_return(6)
      # に置き換える。
      allow(Users::GuestSessionsController.cache_store).to receive(:increment).and_return(6)

      expect { post guest_sign_in_path }.not_to change(User.guest, :count)

      aggregate_failures do
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq I18n.t("users.guest_sessions.flash_message.rate_limited")
      end
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/users/guest_sessions_spec.rb
```

Expected: FAIL。`NameError: undefined local variable or method 'guest_sign_in_path'`。

- [ ] **Step 3: i18n キーを足す**

`config/locales/views/ja.yml` の `defaults:` → `flash_message:` の `record_not_found` の下に1行足す。

```yaml
      guest_not_allowed: ゲストではこの操作はできません
```

さらに `users:` の直下（`sessions:` の前）に足す。

```yaml
    guest_sessions:
      flash_message:
        signed_in: ゲストとしてログインしました。デモ用のデータが登録されています
        rate_limited: 短時間にゲストログインを繰り返しています。しばらくしてから再度お試しください
```

（`guest_not_allowed` は Task 7 で使う。i18n の編集を1回にまとめるためここで足しておく。）

- [ ] **Step 4: ルートを足す**

`config/routes.rb` の `devise_scope :user do ... end` ブロックの直後に足す。

```ruby
  # ゲストログイン（訪問者ごとに使い捨てのユーザーを発行する）
  post "guest_sign_in", to: "users/guest_sessions#create", as: :guest_sign_in
```

- [ ] **Step 5: コントローラを実装する**

`app/controllers/users/guest_sessions_controller.rb` を作成する。

```ruby
# frozen_string_literal: true

# ゲストログイン。訪問者ごとに使い捨ての User を発行する。
#
# 本番に Solid Queue のワーカーが常駐していないため、古いゲストの削除は定期ジョブ
# ではなくこのリクエストの中で行う。ゲストを増やす経路と減らす経路が同一なので、
# 増加と削除が自動的に釣り合う。
class Users::GuestSessionsController < ApplicationController
  skip_before_action :authenticate_user!

  # ボタン連打によるアカウント量産を防ぐ。RegretSummariesController で既に
  # rate_limit を使っているので、同じ流儀に揃える。
  rate_limit to: 5, within: 1.hour,
             by: -> { request.remote_ip },
             with: -> { redirect_to root_path, alert: t("users.guest_sessions.flash_message.rate_limited") },
             only: :create

  def create
    purge_expired_guests
    user = GuestUserBuilder.call
    sign_in(user)
    # 時間切れで削除されたあとに「何が起きたか」を説明するための印。
    # sign_in の後に置く。
    session[:guest_sign_in] = true

    redirect_to mypage_path, notice: t("users.guest_sessions.flash_message.signed_in")
  end

  private

  # 掃除が失敗してもログインは通す。閲覧者にとってはデモが見られることが主目的で、
  # 掃除は次の訪問者が来たときにやり直せる。ただし握りつぶさずログには残す。
  def purge_expired_guests
    GuestUserPurger.call(except_id: current_user&.id)
  rescue StandardError => e
    Rails.logger.error("[GuestUserPurger] #{e.class}: #{e.message}")
  end
end
```

- [ ] **Step 6: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/users/guest_sessions_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 7: RuboCop を通す**

```bash
docker compose exec web bin/rubocop app/controllers/users/guest_sessions_controller.rb spec/requests/users/guest_sessions_spec.rb config/routes.rb
```

Expected: no offenses。

- [ ] **Step 8: コミット**

```bash
git add app/controllers/users/guest_sessions_controller.rb config/routes.rb config/locales/views/ja.yml spec/requests/users/guest_sessions_spec.rb
git commit -m "feat: ゲストログインの入口を追加 #285"
```

---

### Task 7: ゲストに許可しない操作を塞ぐ

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/users/registrations_controller.rb`
- Modify: `app/controllers/users/passwords_controller.rb`
- Modify: `app/controllers/regret_summaries_controller.rb`
- Modify: `app/views/users/registrations/show.html.erb`
- Test: `spec/requests/guest_restrictions_spec.rb`

**Interfaces:**
- Consumes: `users.guest`（Task 1）、i18n キー `defaults.flash_message.guest_not_allowed`（Task 6 で追加済み）
- Produces: `ApplicationController#reject_guest`（各コントローラが `before_action` で使う）

- [ ] **Step 1: 失敗するテストを書く**

`spec/requests/guest_restrictions_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe "ゲストへの操作制限", type: :request do
  let(:guest) { GuestUserBuilder.call }
  let(:message) { I18n.t("defaults.flash_message.guest_not_allowed") }

  before { sign_in guest }

  # UI からリンクを消すだけではルートが残るため、サーバ側で塞げていることを直接叩いて確認する。
  shared_examples "ゲストを拒否する" do
    it "マイページへリダイレクトし、理由を表示すること" do
      request_action

      aggregate_failures do
        expect(response).to redirect_to(mypage_path)
        expect(flash[:alert]).to eq message
      end
    end
  end

  describe "GET /users/edit（アカウント編集）" do
    def request_action = get edit_user_registration_path

    include_examples "ゲストを拒否する"
  end

  describe "PUT /users（アカウント更新）" do
    def request_action = put user_registration_path, params: { user: { name: "変更後" } }

    include_examples "ゲストを拒否する"

    it "名前が変わらないこと" do
      expect { request_action }.not_to change { guest.reload.name }
    end
  end

  describe "DELETE /users（アカウント削除）" do
    def request_action = delete user_registration_path

    include_examples "ゲストを拒否する"

    it "ユーザーが残ること" do
      request_action

      expect(User.exists?(guest.id)).to be true
    end
  end

  describe "GET /users/password/new（パスワード再設定）" do
    def request_action = get new_user_password_path

    include_examples "ゲストを拒否する"
  end

  describe "PATCH /regret_summary/generate（AI要約の生成）" do
    def request_action = patch generate_regret_summary_path

    include_examples "ゲストを拒否する"

    it "OpenAI を呼ばないこと" do
      expect(RegretSummarizer).not_to receive(:new)

      request_action
    end
  end

  describe "制限していない操作" do
    it "アカウント情報画面は見られること（guest_ のメールが使い捨てであることを伝えるため）" do
      get user_account_path

      expect(response).to have_http_status(:ok)
    end

    it "ただしアカウント情報画面に編集ボタンは出さないこと" do
      get user_account_path

      expect(response.body).not_to include(edit_user_registration_path)
    end

    it "闇の時間の特徴への追記はできること（OpenAI を呼ばないため）" do
      patch append_to_dark_time_regret_summary_path

      expect(flash[:alert]).not_to eq message
    end

    it "後悔記録は作成できること" do
      expect {
        post regret_records_path, params: { regret_record: { content: "テスト" } }
      }.to change(guest.regret_records, :count).by(1)
    end
  end

  describe "実ユーザーのとき" do
    let(:real_user) { create(:user) }

    before { sign_in real_user }

    it "アカウント編集が通ること" do
      get edit_user_registration_path

      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_restrictions_spec.rb
```

Expected: FAIL。ガードが無いため、リダイレクト先やフラッシュが一致しない。

- [ ] **Step 3: ApplicationController に共通ガードを足す**

`app/controllers/application_controller.rb` の `private` セクション、`touch_guest_activity` の直後に足す。

```ruby
  # ゲストに許可しない操作の共通ガード。UI 側でもリンクを出さないが、ルートは残るので
  # サーバ側でも必ず塞ぐ。
  #
  # status: :see_other は redirect_to_not_found に合わせている（DELETE / PATCH からの
  # 遷移で Turbo がリクエストメソッドを引き継がないようにするため）。
  def reject_guest
    return unless current_user&.guest?

    redirect_to mypage_path,
                alert: t("defaults.flash_message.guest_not_allowed"),
                status: :see_other
  end
```

- [ ] **Step 4: 各コントローラに適用する**

`app/controllers/users/registrations_controller.rb` の既存の `before_action -> { authenticate_user!(force: true) }, only: [ :show ]` の直後に足す。

```ruby
  # ゲストはアカウントを編集・削除できない。edit.html.erb が current_password を必須に
  # しているため、そもそもランダムパスワードを知らないゲストには更新が成功しない。
  # フォームを見せて失敗させるより、理由を出して塞ぐ。
  before_action :reject_guest, only: %i[edit update destroy]
```

`app/controllers/users/passwords_controller.rb` のクラス定義の先頭に足す。

```ruby
  # ゲストのメールは guest_xxxx@example.com という架空アドレスで届かない。
  # send_devise_notification は deliver_now で同期送信するため、送るとバウンス処理で
  # リクエストが待たされる。
  before_action :reject_guest
```

`app/controllers/regret_summaries_controller.rb` の `before_action :set_regret_summary, only: :append_to_dark_time` の直後に足す。

```ruby
  # ゲストには生成させない（OpenAI のコストと悪用余地の排除）。代わりにデモ要約を
  # 事前投入してあるため、要約の見た目と闇の時間への追記は体験できる。
  before_action :reject_guest, only: :generate
```

- [ ] **Step 5: アカウント情報画面から編集ボタンを隠す**

`app/views/users/registrations/show.html.erb` の「編集ボタン」ブロックを次のように書き換える。アカウント情報画面自体は見せる（`guest_xxxx@example.com` が表示されることで使い捨てのデモアカウントだと伝わる）が、編集への導線だけを消す。

```erb
      <!-- 編集ボタン -->
      <% unless @user.guest? %>
        <div class="text-center">
          <%= link_to "編集する", edit_user_registration_path, class: "inline-block bg-green-700 hover:bg-green-800 px-6 py-2 rounded-full text-white/90 font-semibold transition duration-200 shadow-md" %>
        </div>
      <% end %>
```

- [ ] **Step 6: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_restrictions_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 7: 既存テストが壊れていないことを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests
```

Expected: PASS。Devise 系コントローラに `before_action` を足したため、ここで request spec 全体を回す。

- [ ] **Step 8: コミット**

```bash
git add app/controllers app/views/users/registrations/show.html.erb spec/requests/guest_restrictions_spec.rb
git commit -m "feat: ゲストにアカウント操作・パスワード再設定・AI要約生成を許可しない #285"
```

---

### Task 8: AI要約のゲスト向け表示

**Files:**
- Modify: `app/views/regret_summaries/_regret_summary.html.erb`
- Test: `spec/requests/guest_regret_summary_spec.rb`

**Interfaces:**
- Consumes: `users.guest`（Task 1）、`GuestUserBuilder.call` が投入する `regret_summary`（Task 3）
- Produces: なし（ビューの出し分けのみ）

- [ ] **Step 1: 失敗するテストを書く**

`spec/requests/guest_regret_summary_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe "ゲストのAI要約表示", type: :request do
  context "ゲストのとき" do
    let(:guest) { GuestUserBuilder.call }

    before do
      sign_in guest
      get regret_records_path
    end

    it "デモ要約の本文が表示されること" do
      expect(response.body).to include(GuestDemoData.regret_summary[:content])
    end

    it "デモ用のサンプルである旨を明記すること" do
      expect(response.body).to include("デモ用のサンプル")
    end

    it "生成ボタンを出さないこと" do
      aggregate_failures do
        expect(response.body).not_to include("要約する")
        expect(response.body).not_to include(generate_regret_summary_path)
      end
    end

    it "闇の時間の特徴へ追記するボタンは出すこと（OpenAI を呼ばないため）" do
      expect(response.body).to include(append_to_dark_time_regret_summary_path)
    end
  end

  context "実ユーザーのとき" do
    let(:user) { create(:user) }

    before do
      create(:regret_record, user: user, favorited: true)
      sign_in user
      get regret_records_path
    end

    it "生成ボタンを出すこと" do
      expect(response.body).to include(generate_regret_summary_path)
    end

    it "デモ用のサンプル文言は出さないこと" do
      expect(response.body).not_to include("デモ用のサンプル")
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_regret_summary_spec.rb
```

Expected: FAIL。ゲストにも生成ボタンが出るため「生成ボタンを出さないこと」が落ちる。

- [ ] **Step 3: パーシャルを書き換える**

`app/views/regret_summaries/_regret_summary.html.erb` を次の内容にする。

```erb
<% regret_summary = current_user.regret_summary %>
<% has_favorites = current_user.regret_records.exists?(favorited: true) %>
<% guest = current_user.guest? %>

<%= turbo_frame_tag "regret_summary", class: "block w-80 md:w-full max-w-5xl mx-auto mb-8" do %>
  <div class="bg-violet-800 text-white/90 rounded-lg shadow px-6 py-5">
    <h2 class="text-lg font-bold mb-3">AIによる後悔の傾向まとめ</h2>

    <% if regret_summary.present? %>
      <p class="text-sm whitespace-pre-wrap wrap-break-word mb-3"><%= regret_summary.content %></p>
      <p class="text-xs text-white/60 mb-4">生成日時: <%= format_datetime(regret_summary.generated_at) %></p>

      <%= button_to "闇の時間の特徴へ追記する",
                    append_to_dark_time_regret_summary_path,
                    method: :patch,
                    form: { data: { turbo_frame: "_top" }, class: "inline-block" },
                    class: "px-5 py-2 rounded-full bg-green-700 hover:bg-green-800 font-semibold transition duration-200" %>
    <% else %>
      <p class="text-sm text-white/80 mb-4">
        お気に入り（★）に登録した記録をもとに、闇の時間に陥りやすい傾向をAIが要約します。
      </p>
    <% end %>

    <div class="mt-4">
      <% if guest %>
        <%# ゲストには生成させない（OpenAI のコストと悪用余地の排除）。事前投入した要約を %>
        <%# 「いま生成された」と誤解させないよう、サンプルである旨を必ず明示する。 %>
        <p class="text-xs text-white/60">
          上の要約はデモ用のサンプルです。ゲストではAIによる要約の生成はご利用いただけません。
        </p>
      <% elsif has_favorites %>
        <%= button_to regret_summary.present? ? "再要約する" : "要約する",
                      generate_regret_summary_path,
                      method: :patch,
                      form: { data: { turbo_frame: "_top" }, class: "inline-block" },
                      class: "px-5 py-2 rounded-full bg-blue-500 hover:bg-blue-600 font-semibold transition duration-200" %>
        <p class="text-xs text-white/60 mt-2">お気に入りのうち最新<%= RegretSummarizer::MAX_RECORDS %>件をもとに要約します。</p>
      <% else %>
        <p class="text-xs text-white/60">★お気に入りに登録すると要約できます</p>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_regret_summary_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 5: コミット**

```bash
git add app/views/regret_summaries/_regret_summary.html.erb spec/requests/guest_regret_summary_spec.rb
git commit -m "feat: ゲストにはデモ要約を見せ、生成ボタンを出さない #285"
```

---

### Task 9: ゲスト利用中バッジ

**Files:**
- Create: `app/views/shared/_guest_badge.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Test: `spec/requests/guest_badge_spec.rb`

**Interfaces:**
- Consumes: `users.guest`（Task 1）
- Produces: なし（レイアウトへの表示のみ）

- [ ] **Step 1: 失敗するテストを書く**

`spec/requests/guest_badge_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe "ゲスト利用中バッジ", type: :request do
  context "ゲストのとき" do
    let(:guest) { GuestUserBuilder.call }

    before { sign_in guest }

    # _hamburger_menu は4画面でしか描画されないため、レイアウトに置いて全画面で出す。
    it "マイページで表示されること" do
      get mypage_path

      expect(response.body).to include("ゲスト利用中")
    end

    it "ハンバーガーメニューの無いフォーム画面でも表示されること" do
      get new_light_time_path

      expect(response.body).to include("ゲスト利用中")
    end

    it "登録への導線は置かないこと（データが引き継がれると誤解させないため）" do
      get mypage_path

      expect(response.body).not_to include(new_user_registration_path)
    end
  end

  context "実ユーザーのとき" do
    before { sign_in create(:user) }

    it "表示しないこと" do
      get mypage_path

      expect(response.body).not_to include("ゲスト利用中")
    end
  end

  context "未ログインのとき" do
    it "表示しないこと" do
      get root_path

      expect(response.body).not_to include("ゲスト利用中")
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_badge_spec.rb
```

Expected: FAIL。バッジが未実装のため最初の example が落ちる。

- [ ] **Step 3: バッジのパーシャルを作る**

`app/views/shared/_guest_badge.html.erb` を作成する。

```erb
<%# ゲスト利用中であることを全画面で示すバッジ。
    _hamburger_menu は4画面でしか描画されないためレイアウトに置く。
    左上はハンバーガーボタン、右上はユーザーカードと浄化タイマーカードが占めているので下部中央に配置する。
    登録への導線は置かない。リンクがあると「続きから使える」と期待させるが、データは引き継がれないため。 %>
<% if user_signed_in? && current_user.guest? %>
  <div class="fixed bottom-4 left-1/2 -translate-x-1/2 z-70 pointer-events-none">
    <span class="inline-block rounded-full bg-zinc-900/80 text-white/90 text-xs px-4 py-2 shadow-lg">
      ゲスト利用中
    </span>
  </div>
<% end %>
```

- [ ] **Step 4: レイアウトから描画する**

`app/views/layouts/application.html.erb` の `<%= render 'shared/flash_message' %>` の直後に足す。

```erb
    <%= render "shared/guest_badge" %>
```

- [ ] **Step 5: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/guest_badge_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 6: 既存の System Spec が壊れていないことを確認する**

```bash
docker compose exec web bundle exec rspec spec/system
```

Expected: PASS。`Capybara.ignore_hidden_elements = false` の設定下で固定要素を足したため、ここで System Spec 全体を回す。

- [ ] **Step 7: コミット**

```bash
git add app/views/shared/_guest_badge.html.erb app/views/layouts/application.html.erb spec/requests/guest_badge_spec.rb
git commit -m "feat: ゲスト利用中バッジを全画面に表示する #285"
```

---

### Task 10: ゲストログインボタンの設置

**Files:**
- Create: `app/views/shared/_guest_sign_in_button.html.erb`
- Modify: `app/views/static_pages/home.html.erb:39-42`
- Modify: `app/views/users/sessions/new.html.erb:34`
- Test: `spec/system/guest_sign_ins_spec.rb`

**Interfaces:**
- Consumes: `guest_sign_in_path`（Task 6）
- Produces: なし（ビューのみ）

- [ ] **Step 1: 失敗するテストを書く**

`spec/system/guest_sign_ins_spec.rb` を作成する。

```ruby
require "rails_helper"

RSpec.describe "ゲストログイン", type: :system do
  describe "ホーム画面から" do
    before { visit root_path }

    it "ボタンからログインしてマイページに入れること" do
      click_button "ゲストとして試す", match: :first

      expect(page).to have_content I18n.t("mypages.show.title")
    end

    it "利用規約への同意を明記していること" do
      expect(page).to have_content "利用規約"
    end
  end

  describe "ログイン画面から" do
    before { visit new_user_session_path }

    it "ボタンからログインできること" do
      click_button "ゲストとして試す", match: :first

      expect(page).to have_content I18n.t("mypages.show.title")
    end
  end

  describe "ログイン後の画面" do
    before do
      visit root_path
      click_button "ゲストとして試す", match: :first
    end

    it "ゲスト利用中バッジが出ること" do
      expect(page).to have_content "ゲスト利用中"
    end

    it "デモデータが表示され、ポモドーロを開始できる状態であること" do
      expect(page).to have_link "スタート"
    end

    it "マイステータスにデモの記録が反映されていること" do
      visit mystatus_path

      expect(page).to have_content I18n.t("mystatuses.show.title")
    end
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/system/guest_sign_ins_spec.rb
```

Expected: FAIL。`Capybara::ElementNotFound: Unable to find button "ゲストとして試す"`。

- [ ] **Step 3: ボタンのパーシャルを作る**

`app/views/shared/_guest_sign_in_button.html.erb` を作成する。

```erb
<%# ゲストログインのボタン。omniauth と同じく POST が必要なので button_to を使う。
    チェックボックスは置かず、規約への同意はボタン下の明記で代える（閲覧者のクリックを増やさないため）。 %>
<div class="text-center">
  <%= button_to "ゲストとして試す",
                guest_sign_in_path,
                class: "inline-block bg-emerald-600 hover:bg-emerald-700 text-white/90 px-4 py-2 rounded-lg transition duration-200 text-sm md:text-base font-semibold" %>

  <p class="mt-2 text-xs text-zinc-700">
    ゲストとして試すと
    <%= link_to "利用規約", terms_path, target: "_blank", rel: "noopener", class: "text-blue-700 hover:text-blue-800 underline" %>
    と
    <%= link_to "プライバシーポリシー", privacy_path, target: "_blank", rel: "noopener", class: "text-blue-700 hover:text-blue-800 underline" %>
    に同意したものとみなします。
  </p>
</div>
```

- [ ] **Step 4: ホーム画面に置く**

`app/views/static_pages/home.html.erb` の CTA ブロック（`<div class="flex justify-center items-center gap-6">` から対応する `</div>` まで）の直後に足す。

```erb
    <div class="mt-4">
      <%= render "shared/guest_sign_in_button" %>
    </div>
```

- [ ] **Step 5: ログイン画面に置く**

`app/views/users/sessions/new.html.erb` の `<%= render "users/shared/google_omniauth" %>` の直後に足す。

```erb
      <div class="mt-4">
        <%= render "shared/guest_sign_in_button" %>
      </div>
```

- [ ] **Step 6: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/system/guest_sign_ins_spec.rb
```

Expected: PASS（全 example）。失敗した場合は `tmp/screenshots` のスクリーンショットを確認する。

- [ ] **Step 7: コミット**

```bash
git add app/views/shared/_guest_sign_in_button.html.erb app/views/static_pages/home.html.erb app/views/users/sessions/new.html.erb spec/system/guest_sign_ins_spec.rb
git commit -m "feat: ホーム画面とログイン画面にゲストログインボタンを設置 #285"
```

---

### Task 11: ログアウトの遷移先と時間切れの案内

**Files:**
- Modify: `app/controllers/users/sessions_controller.rb`
- Modify: `app/views/mypages/show.html.erb`
- Modify: `config/locales/views/ja.yml`
- Test: `spec/requests/users/guest_sessions_spec.rb`（Task 6 で作成済みのファイルに追記）

**Interfaces:**
- Consumes: `session[:guest_sign_in]`（Task 6）、`users.guest`（Task 1）
- Produces: i18n キー `users.sessions.flash_message.guest_expired`

- [ ] **Step 1: 失敗するテストを書く**

`spec/requests/users/guest_sessions_spec.rb` の一番外側の `RSpec.describe` ブロックの末尾（最後の `end` の直前）に追記する。

```ruby
  describe "DELETE /users/sign_out（ゲストのログアウト）" do
    before { post guest_sign_in_path }

    it "トップページへ戻すこと" do
      delete destroy_user_session_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "DELETE /users/sign_out（実ユーザーのログアウト）" do
    before { sign_in create(:user) }

    it "ログイン画面へ戻すこと" do
      delete destroy_user_session_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "利用時間切れの案内" do
    it "削除されたゲストがログイン画面に来たら理由を説明すること" do
      post guest_sign_in_path
      # 時間切れ削除を再現する（セッションのクッキーは残ったまま）
      User.guest.delete_all

      get new_user_session_path

      expect(response.body).to include I18n.t("users.sessions.flash_message.guest_expired")
    end

    it "一度表示したら消えること（印を削除するため）" do
      post guest_sign_in_path
      User.guest.delete_all

      get new_user_session_path
      get new_user_session_path

      expect(response.body).not_to include I18n.t("users.sessions.flash_message.guest_expired")
    end

    it "通常のログアウト後には表示しないこと（セッションがリセットされるため）" do
      post guest_sign_in_path
      delete destroy_user_session_path

      get new_user_session_path

      expect(response.body).not_to include I18n.t("users.sessions.flash_message.guest_expired")
    end

    it "ゲストを経ていない訪問者には表示しないこと" do
      get new_user_session_path

      expect(response.body).not_to include I18n.t("users.sessions.flash_message.guest_expired")
    end
  end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/users/guest_sessions_spec.rb
```

Expected: FAIL。ゲストのログアウトが `new_user_session_path` に行き、`guest_expired` の i18n キーも未定義（`translation missing`）。

- [ ] **Step 3: i18n キーを足す**

`config/locales/views/ja.yml` の `users:` → `sessions:` の下、`new:` の前に足す。

```yaml
      flash_message:
        guest_expired: ゲストの利用時間が終了したため、ログアウトしました。もう一度ゲストログインからお試しいただけます
```

- [ ] **Step 4: SessionsController を実装する**

`app/controllers/users/sessions_controller.rb` を次の内容にする。

```ruby
# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  # GET /resource/sign_in
  def new
    # ゲストのセッションが張られていたのにユーザーが居ない = 利用時間切れで削除された後。
    # Devise の既定文言（ログインもしくはアカウント登録してください）では理由が伝わらない
    # ため、ゲスト向けの説明に差し替える。
    #
    # カスタムの FailureApp は作らない。認証失敗を全面的に差し替えることになり
    # 影響範囲が広すぎる。
    flash.now[:alert] = t("users.sessions.flash_message.guest_expired") if session.delete(:guest_sign_in)
    super
  end

  # DELETE /resource/sign_out
  def destroy
    # sign_out 後は current_user が nil になり、after_sign_out_path_for には
    # スコープ（:user）しか渡ってこない。判定はここで控えておく。
    @signing_out_guest = current_user&.guest?
    super
  end

  protected

  # ゲストはデモを終えた閲覧者なので、ログイン画面ではなくトップページへ戻す。
  def after_sign_out_path_for(resource_or_scope)
    @signing_out_guest ? root_path : super
  end
end
```

- [ ] **Step 5: ログアウトボタンの文言をゲスト向けに変える**

`app/views/mypages/show.html.erb` のログアウトリンク（`<%= link_to "ログアウト", destroy_user_session_path, ... %>`）を次のように書き換える。

```erb
        <%= link_to current_user.guest? ? "ゲストを終了" : "ログアウト", destroy_user_session_path, data: { turbo_method: :delete },  class: "w-full text-xs font-semibold text-center bg-red-500 text-white/90 rounded-full py-1.5 hover:bg-red-600 transition duration-200" %>
```

- [ ] **Step 6: テストが通ることを確認する**

```bash
docker compose exec web bundle exec rspec spec/requests/users/guest_sessions_spec.rb
```

Expected: PASS（全 example）。

- [ ] **Step 7: 全体を回す**

```bash
docker compose exec web bundle exec rspec
```

Expected: PASS。`Users::SessionsController` は全ユーザーのログイン・ログアウトを通るため、ここで必ず全体を回す。

- [ ] **Step 8: RuboCop と Brakeman を通す**

```bash
docker compose exec web bin/rubocop
docker compose exec web bin/brakeman --no-pager
```

Expected: RuboCop は no offenses、Brakeman は新規の警告なし。

- [ ] **Step 9: コミット**

```bash
git add app/controllers/users/sessions_controller.rb app/views/mypages/show.html.erb config/locales/views/ja.yml spec/requests/users/guest_sessions_spec.rb
git commit -m "feat: ゲストのログアウト先と利用時間切れの案内を追加 #285"
```

---

## 完了後の確認

- [ ] **全体テスト**

```bash
docker compose exec web yarn build
docker compose exec web bin/rails tailwindcss:build
docker compose exec web bundle exec rspec
```

Expected: すべて PASS（CI の `rspec` ジョブと同じ順序）。

- [ ] **Lint / セキュリティ**

```bash
docker compose exec web bin/rubocop
docker compose exec web bin/brakeman --no-pager
docker compose exec web bin/bundler-audit check
```

Expected: いずれも警告なし。

- [ ] **手で触って確認する**

1. `docker compose up` して `http://localhost:3000` を開く
2. 「ゲストとして試す」を押す → マイページにデモデータが出て、スタートボタンと浄化タイマーのカードが表示される
3. 下部中央に「ゲスト利用中」バッジが出る
4. マイステータスでグラフに14日分の線が乗る
5. 後悔した1日の記録一覧で、デモ要約が表示され、生成ボタンが出ず「デモ用のサンプルです」が出る
6. アカウント情報から「編集する」を押す → マイページに戻され「ゲストではこの操作はできません」が出る
7. 「ゲストを終了」を押す → トップページに戻る

- [ ] **PR を作成する**

PR 作成前に必ずコードレビューを通すこと（小さな差分でも省略しない）。

実装は `feat/guest-login-285` ブランチで行う。設計ドキュメントを載せた `docs/guest-login-design-285` から分岐させる。

```bash
git push -u origin feat/guest-login-285
gh pr create --title "feat: ゲストログイン機能を追加 #285" --body "$(cat <<'BODY'
## 概要

ポートフォリオの閲覧者が、アカウント登録なしにデモデータ入りで全機能を体験できるようにする。closes #285

## 変更点

- `users` に `guest` / `last_request_at` を追加（ゲスト行のみを索引する部分インデックス付き）
- `GuestDemoData` / `GuestUserBuilder` / `GuestUserPurger` を追加
- `POST /guest_sign_in` を追加し、ホーム画面とログイン画面にボタンを設置
- ゲストにはアカウント編集・削除、パスワード再設定、AI要約の生成を許可しない
- 全画面に「ゲスト利用中」バッジを表示
- ゲストのログアウトはトップページへ。利用時間切れのときは理由を説明する

## 設計

`docs/superpowers/specs/2026-09-15-guest-login-design.md` に判断と根拠をまとめてある。特に次の2点は壊しやすいので注意:

- デモの活動記録は必ず昨日以前にする（今日の記録を入れると浄化タイマーのブロックが不当に払い出される）
- 削除は `dependent: :destroy` ではなく一括 `delete_all`（Neon では往復回数が実行時間を決めるため）

## 動作確認

- `bundle exec rspec` / `bin/rubocop` / `bin/brakeman` がすべて通ること
- 手動確認の手順は実装計画の「完了後の確認」に記載

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

---

## 設計との対応

| 設計の節 | 実装タスク |
|---|---|
| 5.1 データモデル | Task 1 |
| 5.2 入口 | Task 6（ルート・コントローラ）/ Task 10（ボタン・規約明記） |
| 5.3 ゲストの生成 | Task 3 |
| 5.4 デモデータ | Task 2 |
| 5.5 最終アクセス時刻の更新 | Task 5 |
| 5.6 削除 | Task 4（サービス）/ Task 6（呼び出し） |
| 5.7 ゲストに制限する操作 | Task 7 |
| 5.8 AI要約の見せ方 | Task 8 |
| 5.9 ゲスト表示 | Task 9 |
| 5.10 ログアウトと時間切れの案内 | Task 11 |
| 8. テスト方針 | 各タスクの Step 1（テストファースト） |
