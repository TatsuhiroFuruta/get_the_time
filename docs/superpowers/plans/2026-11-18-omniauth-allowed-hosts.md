# omniauth 2.2.0 取り込みと allowed_hosts 設定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dependabot PR #345（omniauth 2.1.4 → 2.2.0）を取り込み、同梱のセキュリティ修正（GHSA-m27g-v28p-f9fx / CVE-2026-63183、偽装ホスト対策）を `OmniAuth.config.allowed_hosts` の設定で実際に有効にする。

**Architecture:** `config/initializers/omniauth.rb` を新設し、本番だけ `OmniAuth.config.allowed_hosts` に `Rails.application.config.hosts`（`config/environments/production.rb` で定義済みの 3 ドメイン）を渡す。ドメイン一覧の正本は production.rb の 1 か所のまま。

**Tech Stack:** Rails 8.1 / Devise / omniauth 2.2.0 / omniauth-google-oauth2 / omniauth-rails_csrf_protection / RSpec

**Spec:** 設計書ファイルはなし（2026-11-18 のチャットで承認済みの短い設計。下の Global Constraints に要点を転記）

## Global Constraints

- 設定は本番のみ（`Rails.env.production?`）。開発の `config.hosts` には IPAddr 等が入り、`allowed_hosts` は文字列か正規表現しか受け付けないため
- `full_host` は設定しない（`www` / `onrender.com` からのログインでセッションが切れるため不採用）
- ほかの gem は更新しない
- 作業ブランチは #345 のブランチ `dependabot/bundler/omniauth-2.2.0` を土台に新しく切り、Gemfile.lock の更新と設定を 1 つの PR にまとめる
- コメント・spec の説明は日本語、文字列はダブルクォート
- コミット / PR には Issue 番号 `#NNN` を付ける。コミットに Claude-Session の URL 行を入れない

## 確認済みの gem の挙動（v2.2.0 ソース）

- `lib/omniauth/strategy/hosts.rb#allowed_host?`: `full_host` 未設定かつ `allowed_hosts` が nil なら常に true。文字列はホスト全体と大文字小文字無視で一致、正規表現はホスト全体に一致
- `request_call` / `callback_call` の冒頭で判定し、不一致なら `fail!(:invalid_host, ...)` → Devise の on_failure 経由で `Users::OmniauthCallbacksController#failure`（`root_path` へ「Google認証に失敗しました。」）
- **`OmniAuth.config.test_mode = true` のときは `mock_call!` に分岐するため判定が動かない**。spec では一時的に `test_mode` を false にする（`spec/support/omniauth.rb` がグローバルに true にしている）

## Review Focus

- `config.hosts` に Rails 流のサブドメイン指定（`".get-the-time.com"` など先頭ドット）や IPAddr を足すと、OmniAuth では文字通りの一致になり本番の Google ログインが全滅する → initializer にコメントで明記（Task 2 Step 3）
- spec で `test_mode` / `allowed_hosts` を書き換えたまま戻し忘れると、他の Google 認証 spec が実通信側へ流れて壊れる → `around` で必ず元に戻す（Task 2 Step 1）
- 許可ホストでも Google への `redirect_uri` が許可ホストで組み立てられていること → spec で確認（Task 2 Step 1）
- テスト・開発環境では `allowed_hosts` が nil のまま（既存の System Spec / 開発ログインが壊れない）→ spec で確認（Task 2 Step 1）
- ホストの大文字小文字違い（`Get-The-Time.com`）は gem 側で許可される → 追加テスト不要（gem の仕様）

---

### Task 1: Issue と作業ブランチ

- [ ] **Step 1: Issue を立てる**

`gh issue create` でタイトル「omniauth 2.2.0 を取り込み、allowed_hosts で偽装ホスト対策を有効にする」。本文に #345・GHSA-m27g-v28p-f9fx・「バージョンを上げるだけでは防御が有効にならない」こと・本番のみ設定する理由を書く。番号を以降 `#NNN` として使う。

- [ ] **Step 2: ブランチを切る**

```bash
git fetch origin
git switch -c fix/omniauth-allowed-hosts origin/dependabot/bundler/omniauth-2.2.0
docker compose exec web bundle install
```

Expected: `Gemfile.lock` の omniauth が `2.2.0`。

---

### Task 2: allowed_hosts の設定と spec

**Files:**
- Create: `config/initializers/omniauth.rb`
- Create: `spec/requests/users/omniauth_allowed_hosts_spec.rb`

**Interfaces:**
- Consumes: `Rails.application.config.hosts`（production.rb）、`Users::OmniauthCallbacksController#failure`
- Produces: 本番の `OmniAuth.config.allowed_hosts`

- [ ] **Step 1: spec を書く**

`spec/requests/users/omniauth_allowed_hosts_spec.rb`（`type: :request`）。`around` で `OmniAuth.config.test_mode` と `OmniAuth.config.allowed_hosts` を退避し、`test_mode = false`、`allowed_hosts = ["get-the-time.com"]` にして実行後に必ず戻す（`ensure`）。

- `it "許可したホストでは Google の認可画面へリダイレクトする"`: `host! "get-the-time.com"` → `post user_google_oauth2_omniauth_authorize_path`
  - `expect(response.location).to start_with("https://accounts.google.com/")`
  - `redirect_uri` クエリが `http://get-the-time.com/users/auth/google_oauth2/callback` であること（`Rack::Utils.parse_query(URI(response.location).query)["redirect_uri"]`）
- `it "許可していないホストでは認証を中断してトップへ戻す"`: `host! "evil.example.com"` → 同じ POST
  - `expect(response).to redirect_to(root_path)`
  - `expect(flash[:alert]).to eq("Google認証に失敗しました。")`
  - `expect(response.location).not_to include("accounts.google.com")`
- 別の `describe`（`around` の外）で `it "テスト環境では allowed_hosts を設定しない"`: `expect(OmniAuth.config.allowed_hosts).to be_nil`

- [ ] **Step 2: 実行して状態を確認**

Run: `docker compose exec web bundle exec rspec spec/requests/users/omniauth_allowed_hosts_spec.rb`
Expected: 3 件とも PASS（gem の機能を spec 側で設定して検証しているため、この時点で通る。通らなければ CSRF 検証や on_failure の経路を調べる。`invalid_host` で 500 になる・Google へ飛ぶなら設計の前提が崩れているので止めて報告）。

- [ ] **Step 3: initializer を作る**

`config/initializers/omniauth.rb`: `if Rails.env.production?` で `OmniAuth.config.allowed_hosts = Rails.application.config.hosts` 。コメントに以下を日本語で書く:
- 目的（GHSA-m27g-v28p-f9fx。コールバック URL を偽装可能な Host / X-Forwarded-Host から組み立てるのを防ぐ。未設定だと防御が無効で警告ログが出る）
- 本番のみの理由（開発の `config.hosts` は IPAddr 等を含む）
- **`config.hosts` に先頭ドットのサブドメイン指定や IPAddr を足すと OmniAuth では一致しなくなり本番の Google ログインが壊れる。足す場合はここで正規表現に変換すること**
- `full_host` を使わない理由（複数ドメインからのログインでセッションが切れる）

- [ ] **Step 4: 本番設定で値が入ることを確認**

Run: `docker compose exec -e RAILS_ENV=production -e SECRET_KEY_BASE_DUMMY=1 web bin/rails runner 'p OmniAuth.config.allowed_hosts'`
Expected: `["get-the-time.com", "www.get-the-time.com", "get-the-time.onrender.com"]`（DB 接続等で起動できない場合はその旨を記録し、Step 1 の spec と目視確認で代える）

- [ ] **Step 5: 全体の確認**

Run: `docker compose exec web bundle exec rspec` / `docker compose exec web bin/rubocop` / `docker compose exec web bin/brakeman --no-pager`
Expected: すべて成功

- [ ] **Step 6: Commit**

```bash
git add config/initializers/omniauth.rb spec/requests/users/omniauth_allowed_hosts_spec.rb
git commit -m "fix: 本番で OmniAuth の allowed_hosts を設定し偽装ホスト対策を有効にする (#NNN)"
```

---

### Task 3: レビューと PR

- [ ] **Step 1: コードレビュー**（PR 作成前に必ず通す）
- [ ] **Step 2: push と PR 作成**: ベース `main`。本文に `Closes #NNN`、#345 の内容を取り込む旨、gem の挙動の確認結果、本番デプロイ後に Google ログインを `get-the-time.com` で 1 回確認する手順を書く
- [ ] **Step 3: マージ後**: #345 が自動で閉じなければコメントを付けて閉じる。本番で Google ログインと、Render のログに OmniAuth の警告が出ていないことを確認
