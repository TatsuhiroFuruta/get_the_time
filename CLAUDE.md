# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**Get The Time** は Rails 8.1 製の Web アプリで、ユーザーの自由時間を「光の時間」（本来望んでいる行動の時間）と「闇の時間」（SNS・動画などの誘惑に費やす時間）に分け、ポモドーロ・テクニック風のタイマーで「本来の自分」（自己像形成度合いの指標）を計測するサービスです。ドメイン仕様の全体像は `README.md` に記載されています。`idle_duration`、`desired_self_percentage`、`PurificationTime` のステートマシン等のフィールドはこの仕様に基づいているため、モデルの意味を変更する前に必ず `README.md` を読んでください。

デフォルトロケールは `:ja` です（`config/application.rb`）。UI 文字列、フラッシュメッセージ、コメント、バリデーションメッセージはすべて日本語で記述されています。新しい文言を追加する際もこの規約に従ってください。i18n ファイルは `config/locales/` 配下にあります。

## 技術スタック

- Ruby 3.3.6, Rails 8.1.3
- PostgreSQL（本番は Neon）、デプロイ先は Render
- Hotwire (Turbo + Stimulus)、esbuild、Tailwind CSS v4
- Solid Queue / Solid Cache / Solid Cable
- 認証: Devise（+ devise-i18n）、検索: Ransack、ページネーション: Kaminari
- テスト: RSpec + FactoryBot + Capybara + Selenium

## よく使うコマンド

本プロジェクトの開発環境は `compose.yml` による Docker 構成が前提です。`web` コンテナの起動コマンドが `bin/dev` を含んでいるため、`docker compose up` するだけで Rails サーバー・esbuild watcher・Tailwind watcher が同時に立ち上がります。ローカルに直接 Ruby / Node を入れている場合は `docker compose exec web` プレフィックスを外し、各コマンドをそのまま実行してください。

```bash
# 開発環境の起動（db / web / chrome の 3 コンテナ）
docker compose up
docker compose up -d                  # バックグラウンド起動
docker compose down                   # 停止

# コンテナ内シェル
docker compose exec web bash

# テスト一式（本プロジェクトは Minitest ではなく RSpec を使用。bin/ci の `bin/rails test` 記述は無視してよい）
docker compose exec web bundle exec rspec
docker compose exec web bundle exec rspec spec/models/user_spec.rb              # 単一ファイル
docker compose exec web bundle exec rspec spec/models/user_spec.rb:42           # 行番号指定での単一 example 実行

# Lint / セキュリティ
docker compose exec web bin/rubocop                  # rubocop-rails-omakase + ダブルクォート強制の設定
docker compose exec web bin/rubocop -a               # 自動修正
docker compose exec web bin/brakeman --no-pager
docker compose exec web bin/bundler-audit check

# DB
docker compose exec web bin/rails db:prepare
docker compose exec web bin/rails db:seed

# アセットビルド（CI では両方実行される）
docker compose exec web yarn build
docker compose exec web bin/rails tailwindcss:build

# その他のワンライナー例
docker compose exec web bin/rails console
docker compose exec web bin/rails routes
docker compose exec web bin/rails generate migration AddFooToBars name:string
```

### Docker 開発環境の構成

`compose.yml` は次の 3 コンテナを起動します:
- `db`: PostgreSQL（`postgresql_data` ボリュームで永続化、ホストの `5432` を公開）
- `web`: Rails アプリ。リポジトリを `/myapp` にマウントし、起動時に `bundle install && rails db:prepare && bin/dev` を実行。ホストの `3000` を公開
- `chrome`: Selenium Standalone Chromium。System Spec から利用

`web` コンテナ内では `SELENIUM_DRIVER_URL=http://chrome:4444/wd/hub` が設定されており、Capybara がリモートドライバに切り替わります（後述）。

### CI

GitHub Actions (`.github/workflows/ci.yml`) は 3 つのジョブを並列実行します:
- `scan_ruby`: Brakeman + bundler-audit
- `lint`: RuboCop（キャッシュあり）
- `rspec`: `yarn build` → `tailwindcss:build` → `db:test:prepare` → `bundle exec rspec`

System Spec が失敗した場合は `tmp/screenshots` のスクリーンショットがアーティファクトとしてアップロードされます。`bin/ci` / `config/ci.rb` は古いローカル CI ランナーで、いまだに `bin/rails test` を参照していますが、正本は GitHub workflow です。

## アーキテクチャ

### ドメインモデル（`db/schema.rb`）

`User` は以下を所有します:
- `has_many :light_times` — 望んでいる行動。`is_current: true` が立つレコードはちょうど 1 件で、切り替えはトランザクション内の `LightTime.switch_current!` で行います。
- `has_one :dark_time` — ユーザーごとに 1 件の闇の時間プロフィール（`user_id` に unique 制約）。
- `has_many :activity_records` — ポモドーロセッションごとの記録。`belongs_to :light_time`。
- `has_one :purification_time` — 浄化タイマー（ユーザーごとに 1 件）。

`ApplicationController` で `authenticate_user!` を全体に適用しているため、すべてのコントローラはデフォルトで認証必須です。

### 活動記録のフロー

`ActivityRecord` のコールバックが他モデルへの副作用を 2 つ走らせるため、レコード作成は単純な INSERT ではありません:
- `before_save :calculate_desired_self_percentage` — `(total_duration - idle_duration) / total_duration` を算出。
- `after_create :grant_purification_time` — `user.with_lock` 内でユーザーの `PurificationTime` に `(total_duration / 30).floor * 10` 分を加算。この除数・乗数は「本番用」の値で、コメントアウトされた「確認用」のバリエーションも残っています。

`ActivityRecordForm`（`app/forms/` 配下、`config.autoload_paths << Rails.root.join("app/forms")` でオートロード）がコントローラから使われる書き込み経路です。`ActivityRecord` の作成と、関連する `LightTime#characteristic` および `DarkTime#characteristic` の更新を単一トランザクションでまとめています。**ポモドーロのフローから活動記録を作成する際は、このフォームオブジェクトを必ず経由してください**。直接 `ActivityRecord.create` を呼ぶと特徴量の更新が漏れます。

### ポモドーロ / タイマーのルーティング

`config/routes.rb` には `GET /activity_records/pomodoro_timer` という非標準の collection ルートがあり、タイマーのエントリポイントになっています。`new` アクションは `params[:activity_record_form]` が無い場合このパスへリダイレクトします。つまり、タイマー計測後でないとフォームに辿り着けない設計です。コントローラをリファクタする際もこのガードは残してください。

`PurificationTime` はステートマシン（`enum status: { idle, running, paused }`）で、`start!` / `stop!` / `reset!` というカスタムメソッドが `resource :purification_time` の `PATCH` ルートとして公開されています。これらを汎用的な `update` に置き換えないでください。状態遷移によって不変条件（例: `stop!` は残り時間に応じて finish か pause かを判定する）が守られています。

### Ransack の許可リスト

Ransack 検索はモデルごとに明示的に許可された属性のみ可能です:
- `ActivityRecord.ransackable_attributes` → `["comment"]`、`ransackable_associations` → `["light_time"]`
- `LightTime.ransackable_attributes` → `["action"]`

検索対象カラムを追加するときは、ここに明示的に追記してください。

### ルートパス

ルートパスは 2 つあります:
- ログイン済み: `authenticated :user { root "mypages#show" }`
- 未ログイン: `root "static_pages#home"`

Devise のコントローラは `app/controllers/users/` 配下でオーバーライドされています。

## テストに関するメモ

- `.rspec` は `spec_helper` のみ require します（`rails_helper` ではない）。Rails が必要な spec では個別に `require "rails_helper"` を行ってください。
- `spec/support/capybara.rb` がドライバ選択を担う**唯一の**ファイルです（先日集約済み）。`SELENIUM_DRIVER_URL` が設定されていれば `:remote_chrome`（Docker 環境）、そうでなければ `:headless_chrome`（CI / ローカル直接実行）が選ばれます。`Capybara.ignore_hidden_elements = false` は意図的な設定です。多くの UI 要素がハンバーガーメニューに隠れているためです。
- Devise の統合ヘルパー（`sign_in`）は `:request` と `:system` の両タイプで読み込まれています（`spec/rails_helper.rb`）。
- `ActiveSupport::Testing::TimeHelpers`（`freeze_time`, `travel_to`）はグローバルに include 済みです。タイマー / 浄化タイマー周りのテストで有用です。

## コードスタイル

`.rubocop.yml` は `rubocop-rails-omakase` を継承しつつ次のオーバーライドを行っています:
- `spec/**/*` も含めてダブルクォート文字列を強制
- `db/schema.rb`、`db/*_schema.rb`、`db/migrate/*` を全 cop の対象外
