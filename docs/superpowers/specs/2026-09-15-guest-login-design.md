# ゲストログイン機能 設計

- 対象 issue: #285
- 作成日: 2026-09-15

## 1. 目的

ポートフォリオの閲覧者が、アカウント登録なしに Get The Time の全機能を体験できるようにする。

## 2. スコープ

### 対象

- 訪問者ごとに使い捨てのゲストアカウントを作成し、デモデータ入りでログインさせる
- 使い終わったゲストアカウントとその関連データを削除する
- ゲストに許可しない操作を制限する

### 対象外

- ゲストが作成したデータの本アカウントへの引き継ぎ
- 実ユーザーの「登録前お試し」導線としての利用
- Solid Queue ワーカーの有効化

実ユーザーのお試しを兼ねない理由は 9.1 に記載する。

## 3. 背景

### 3.1 デモデータなしでは中核機能に到達できない

`app/views/mypages/show.html.erb` の表示は、ほぼすべてが `current_user.light_and_dark_times_present?`（闇の時間あり **かつ** `is_current: true` の光の時間あり）と `@purification_time` の有無で分岐している。新規ユーザーはどちらも満たさないため、ログイン直後のマイページは以下の状態になる。

| 要素 | 空のユーザー |
|---|---|
| ポモドーロのスタートボタン | 非表示 |
| 浄化タイマーのカード | 非表示（`purification_time` は初回付与時に `PurificationTimeGranter` が作るため、レコード自体が存在しない） |
| 「新規」「後悔したと思ったら」リンク | 非表示 |
| マイステータスのグラフ（直近14日） | 全日 0 / nil |
| 生成AI要約 | お気に入りの後悔記録が 0 件のため `NoFavoritesError` |

さらに浄化タイマーは「その日の光の時間の累計30分ごと」に付与される。閲覧者がその場で30分計測しない限り到達できない。README で最も強く打ち出している機能が、登録直後には見られない。

### 3.2 `db/seeds.rb` のデモデータは流用できない

`Faker::Config.locale` はアプリの `default_locale = :ja` を拾うため日本語にはなるが、中身が意味をなさない。開発コンテナでの実行結果:

```
Faker::Lorem.sentence(word_count: 3) → 人口半額壊す。 / まぎらす人口金縛り。
Faker::Lorem.paragraph               → かちゅうがいようたらす。奉仕しゅしょうみさき。
```

該当箇所は活動記録の `task` / `comment`（記録一覧に表示）と、後悔記録の `title` / `content`（カードとして読ませる画面）。加えて `RegretSummarizer` はお気に入りの後悔記録の本文を OpenAI に渡すため、AI要約の入力にもなる。ゲスト用のデモ文言は手書きで用意する。

### 3.3 本番に Solid Queue のワーカーが存在しない

`config/recurring.yml` に production のエントリがあるが、Render 側でワーカーが起動していない（`render.yaml` / `Procfile` はリポジトリに存在せず、`config/deploy.yml` の `SOLID_QUEUE_IN_PUMA: true` は Kamal 用のため Render には適用されない）。既存の `clear_solid_queue_finished_jobs` も動いていない。`User#send_devise_notification` が `deliver_later` ではなく `deliver_now` を使っているのも、この前提と整合している。

したがって定期ジョブによる削除は成立しない。

## 4. 決定事項

| # | 項目 | 決定 |
|---|---|---|
| 1 | 対象 | ポートフォリオ閲覧者に割り切る（引き継ぎは作らない） |
| 2 | 初期データ | フルデモ。活動記録は**昨日以前**のみ |
| 3 | AI要約 | デモ要約を事前投入。生成ボタンのみ無効化し、サンプルである旨を明記 |
| 4 | アカウント方式 | 訪問者ごとに使い捨て |
| 5 | 識別 | `users.guest` boolean + `last_request_at`（ゲストのみ10分間引きで更新）、部分インデックス |
| 6 | 削除の起動 | ゲストログイン時のリクエスト駆動。失敗してもログインは通し、ログに記録 |
| 7 | 削除条件 | `guest: true` かつ `last_request_at` が1時間以上前、本人を除外、1回500件まで |
| 8 | 削除方法 | 関連テーブルを `user_id` で一括 `delete_all`（8クエリ固定） |
| 9 | 規約同意 | ボタン下に明記（チェックボックスは置かない） |
| 10 | 制限する操作 | アカウント編集・更新・削除、パスワード再設定、AI要約生成の4つ |
| 11 | ゲスト表示 | 専用バッジは置かない。マイページのユーザーカードで示す（5.9） |
| 12 | 入口 | ホーム画面の CTA + ログイン画面 |
| 13 | ログアウト | 通常と同じくログイン画面へ。文言は「ゲストを終了」（5.10）|
| 14 | レート制限 | ゲスト作成 20回/時間。数える単位は `CF-Connecting-IP`（無ければ `remote_ip`）|
| 15 | 構成 | `GuestDemoData`（文言）/ `GuestUserBuilder`（生成）/ `GuestUserPurger`（削除） |
| 16 | 時間切れの案内 | `session[:guest_sign_in]` を印に、ログイン画面で専用メッセージを表示 |
| 17 | 計測中の保護 | クライアントから定期 ping を送り `last_request_at` を更新する（5.11） |
| 18 | ログイン済みの扱い | ゲストを発行せずマイページへ戻す（5.2） |

## 5. 設計

### 5.1 データモデル

```ruby
add_column :users, :guest, :boolean, default: false, null: false
add_column :users, :last_request_at, :datetime
add_index  :users, :last_request_at, where: "guest"
```

`guest` は以下すべての判定に使う単一の根拠とする。

- 削除対象の特定
- ゲスト向けの UI 出し分け（アカウント編集ボタンの非表示、AI要約の生成ボタンの非表示など）
- AI要約の生成ボタンの無効化
- アカウント削除・編集などの禁止

メールアドレスのパターン（`guest_%`）による識別は採らない。実ユーザーがたまたま似たアドレスを使った場合に巻き込む危険があり、削除処理の条件としては危険すぎる。

`last_request_at` は**ゲストのみ更新する**。実ユーザーは削除対象ではないため、書いても読まれない。全ユーザーで更新すると、読まれない値のために毎リクエスト UPDATE が発生する。部分インデックス（`where: "guest"`）にしているのは、削除の絞り込みがゲスト行に対してのみ行われるため。実ユーザーが増えてもインデックスは小さいまま保たれる。

判定は `User` に集約する（`light_and_dark_times_present?` と同じ流儀）。

```ruby
scope :guest, -> { where(guest: true) }
```

既存ユーザーへの影響は `default: false` で吸収される。ゲストは `email` に `guest_<ランダム>@example.com`、`password` にランダム文字列を入れるため、既存の `validatable` と `password` のスペース禁止バリデーションをそのまま通る。`provider` / `uid` は nil のままで、PostgreSQL では NULL 同士は重複とみなされないため、`[provider, uid]` の unique インデックスとは衝突しない。

### 5.2 入口

```ruby
# config/routes.rb
post "guest_sign_in", to: "users/guest_sessions#create", as: :guest_sign_in
```

**ログイン済みの人にはゲストを発行しない**（決定18）。`sign_in` は Warden のユーザーを無条件に差し替えるため、別タブでログインしたあとにこの画面へ戻って押す、bfcache から復元された古いトップページで押す、といった経路で、本アカウントから使い捨てのゲストへ黙って入れ替わってしまう。すでにゲストの場合も、既存のデモを捨てて作り直す意味がない。

この `before_action` は `rate_limit` より先に宣言する。順番が逆だと、ゲストを作っていないのにレート制限の枠だけを消費する。

```ruby
class Users::GuestSessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: :create
  before_action :redirect_if_signed_in, only: :create

  # ボタン連打によるアカウント量産を防ぐ。RegretSummariesController で
  # 既に rate_limit を使っているので、同じ流儀に揃える。
  # 数える単位は IP なので、上限は「1人あたりの回数」ではなく「同じ回線の向こうに
  # いる人数」で決める。5 にすると同一 NAT 配下の6人目が一度も押していないのに
  # デモを見られない。
  rate_limit to: MAX_SIGN_INS_PER_HOUR, within: 1.hour, by: -> { request.remote_ip },
             with: -> { redirect_to root_path, alert: t(".rate_limited") }

  def create
    purge_expired_guests
    user = GuestUserBuilder.call
    sign_in(user)
    session[:guest_sign_in] = true
    redirect_to mypage_path, notice: t(".signed_in")
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

`session[:guest_sign_in]` は `sign_in` の後に置く。

ボタンの設置は2箇所。

- `app/views/static_pages/home.html.erb` の CTA（「はじめる」「ログイン」の並び）。ホーム画面は `min-h-screen flex items-center justify-center` の1画面完結なので、スクロールなしで見える
- `app/views/users/sessions/new.html.erb`（Google 認証ボタンの下）

いずれもボタン下に「ゲストログインすると利用規約・プライバシーポリシーに同意したものとみなします」をリンク付きで表示する。`User` の `validates :agreement, acceptance:` は `allow_nil: true` が既定のため、`agreement` を渡さなければバリデーションはスキップされる（OmniAuth 経由の作成と同じ挙動）。

### 5.3 ゲストの生成

`GuestUserBuilder`（`app/services/`）が単一トランザクションで以下を作る。

```ruby
User.create!(
  guest: true,
  email: "guest_#{SecureRandom.hex(8)}@example.com",
  password: SecureRandom.hex(16),
  name: "ゲストユーザー",
  last_request_at: Time.current
)
```

`after_create :create_pomodoro_setting` が自動で走るため、ポモドーロ設定は明示的に作らない。

**`last_request_at` を生成時に必ず入れる。** nil のまま作ると `last_request_at < ?` に永久にマッチせず、そのゲストは一度も削除されない。

関連データの投入は `insert_all` で行う。1件ずつ `create!` すると活動記録だけで40往復になり、ネットワーク越しの Neon ではログイン待ち時間に直結する（往復20msなら約0.8秒）。`insert_all` なら生成全体が約10クエリに収まり、往復時間にほぼ影響されない。

`insert_all` はバリデーションもコールバックもバイパスするため、以下をデータ側で担保する。

- `satisfaction` / `progress` / `quality` / `focus` / `fatigue` は `inclusion: { in: 1..5 }` なので nil 不可。全件セットする
- `idle_duration` は `numericality: { greater_than_or_equal_to: 0 }` かつ `total_duration` 以下
- `desired_self_percentage` は `before_save :calculate_desired_self_percentage` が走らないため、`(total_duration - idle_duration) / total_duration` を自分で入れる
- 光の時間は `is_current: true` がちょうど1件（`switch_current!` を通らないため）

### 5.4 デモデータ

文言は `GuestDemoData` に定義し、`GuestUserBuilder` が使う。日付を「生成時刻から N 日前」の相対で組み立てる必要があるため、静的な YAML ではなく Ruby で持つ。文言（何を書くか）と投入処理（どう入れるか）を分けることで、後から文言だけ直せる。

| 種類 | 件数 | 備考 |
|---|---|---|
| 光の時間 | 2〜3件 | うち1件を `is_current: true`。切り替え機能を試せるようにする |
| 闇の時間 | 1件 | `user_id` に unique 制約があるため必ず1件 |
| 活動記録 | 30〜40件 | **昨日以前**の直近14日に分散。`light_time` を散らして Ransack 検索も試せるようにする |
| 後悔記録 | 8〜10件 | うち2〜3件を `favorited: true`（お気に入りフィルタのデモ） |
| 要約 | 1件 | デモ用のサンプル。画面にその旨を明記する |
| 浄化タイマー | 1件 | `remaining_time` に初期値（例: 10分）、`granted_blocks_date: nil` / `granted_blocks_count: 0` |

#### 活動記録を昨日以前に限る理由

`PurificationTimeGranter` は付与数を `floor(その日の光の時間の累計 / 30) - 払い出し済みブロック数` で決める。仮にデモの活動記録を**今日の日付**で90分ぶん入れ、`granted_blocks_count` を 0 のままにすると、閲覧者が1件でも活動記録を作った瞬間に `floor(90/30) - 0 = 3` ブロックが付与される。自分で稼いでいない3ブロックであり、マイページの「次の付与まであと何分」表示も狂う。

昨日以前に限れば今日の累計が 0 になり、`granted_blocks_date: nil` / `granted_blocks_count: 0` のままで整合する。台帳を意識する必要が消える。

グラフは直近14日を描くため線は乗る。今日は「これから」の状態になり、閲覧者は自分でポモドーロを回して浄化タイマーを獲得するという、このアプリの中核体験をそのまま試せる。

浄化タイマーの `remaining_time` は台帳とは独立した値で、実際のモデルでも残時間は日をまたいで持ち越される。初期値を入れておくことは「昨日の残り」として自然に説明がつき、カードが表示されて閲覧者がすぐ開始できる。

### 5.5 最終アクセス時刻の更新

`ApplicationController` に `before_action :touch_guest_activity` を追加する。

```ruby
# ApplicationController
before_action :touch_guest_activity

# ゲストの削除判定にのみ使う。実ユーザーは削除対象ではないため更新せず、nil のままになる。
# 全ユーザーで更新すると、読まれることのない値のために毎リクエスト UPDATE が走る。
# updated_at を動かさずバリデーションもコールバックも走らせないため update_column を使う。
def touch_guest_activity
  return unless current_user&.guest?
  return if current_user.last_request_at&.after?(10.minutes.ago)

  current_user.update_column(:last_request_at, Time.current)
end
```

### 5.11 計測中のゲストを守る定期 ping

5.5 だけでは足りない。**ポモドーロと浄化タイマーの計測は、すべてクライアント側で完結している。**

- `pomodoro_controller.js` の `startTimer` → `onTimerComplete` → `switchToBreakMode` / `switchToWorkMode` に `fetch` は無い
- 30 秒ごとの heartbeat（`activity_lock.js` の `renew()`）は `localStorage` を書くだけ
- `fetch` はコントローラ内に 1 箇所だけで、開始前の浄化タイマー確認の一発きり

つまり計測中はサーバへのリクエストがゼロで、`last_request_at` が更新されない。間引き 10 分を差し引くと実質の猶予は約 50 分しかなく、既定の 25 分 + 休憩 5 分 + 25 分 = 55 分で超える。作業時間は最大 90 分まで設定できるので、1 セッションだけでも超える。**この状態では 5.6 の「50〜60 分の無操作で削除」という前提が成立しない。**

そこで `POST /guest_heartbeat` を用意し、`guest_heartbeat_controller.js` から定期的に叩く。アクションは `head :no_content` を返すだけで、更新は 5.5 の `touch_guest_activity` が担う。

- **計測画面ごとに仕込まず、レイアウトから常時動かす。** silent な画面を列挙する方式は、画面が増えたときに漏れる
- **非表示というだけでは止めない。** ポモドーロは「タイマーを開始して別タブで作業する」のが通常の使い方で、そこで止めると守るべき当のケースを落とす。`activity_lock.js` の `held()`（有効なリースの有無 = 計測中か）で判定し、計測していない放置タブだけを止める
- 実際の UPDATE は 10 分に間引かれるため、ping の間隔を短くしても DB への書き込みは増えない（実測: ping 1 回あたり 1 クエリ、マイページ 1 回の表示は 9 クエリ）
- 間隔は 60 秒。5 分前後にすると Neon の autosuspend の境目に当たり、停止と復帰を繰り返してコールドスタートが挟まる。大きく延ばせば compute は減るが、ping が 1 回失敗しただけで猶予を食い潰す

なお `fetch` は HTTP エラーで reject しないため、CSRF トークンが通らなくても 422 が `catch` にすら引っかからず、ハートビートが黙って動かなくなる。`config/environments/test.rb` は `allow_forgery_protection = false` なので通常の spec では検出できない。検証は `spec/requests/guest_activity_spec.rb` で、その spec だけ本番と同じ設定にして行う（トークン無しで 422 になる負のテスト付き）。

### 5.6 削除

`GuestUserPurger`（`app/services/`）。

```ruby
scope = User.guest.where(last_request_at: ...1.hour.ago).limit(500)
# リクエスト中のゲスト自身は必ず除外する。except_id が nil のとき where.not(id: nil) は
# 「id IS NOT NULL」となり意図が読めなくなるため、値があるときだけ条件を足す。
scope = scope.where.not(id: except_id) if except_id
ids = scope.pluck(:id)

ActivityRecord.where(user_id: ids).delete_all
RegretRecord.where(user_id: ids).delete_all
RegretSummary.where(user_id: ids).delete_all
PurificationTime.where(user_id: ids).delete_all
LightTime.where(user_id: ids).delete_all
DarkTime.where(user_id: ids).delete_all
PomodoroSetting.where(user_id: ids).delete_all
User.where(id: ids).delete_all
```

#### `dependent: :destroy` を使わない理由

`User#destroy` は関連を1行ずつ DELETE するため、1ユーザーあたり約74クエリになる。往復回数が支配的で、ネットワーク越しの Neon では実行時間がレイテンシに比例して伸びる（7.2 参照）。一括 `delete_all` なら件数によらず8クエリで、往復50msでも0.4秒に収まる。

削除対象テーブルの一覧をサービス側にも持つことになるが、7テーブルすべてに `add_foreign_key` が張られているため、関連を追加してここを更新し忘れれば `User` の DELETE が外部キー違反で失敗する。静かに孤児が残るのではなく明示的に落ちる。

#### 猶予を1時間にした理由

`last_request_at` は10分間引きで更新されるため、最大10分古い値になりうる。したがって実際に削除されるまでの無操作時間は「猶予 − 10分」〜「猶予」の範囲になる。

```
猶予30分 → 実際には 20〜30分 の無操作で削除
猶予60分 → 実際には 50〜60分 の無操作で削除
```

30分設定では、20分席を外しただけの閲覧者（電話、会議、昼食）が消される可能性がある。1時間なら50分必要になり、現実的にはほぼ起きない。

**ただしこの計算は「画面を見ている間はリクエストが飛ぶ」ことを前提にしている。** ポモドーロと浄化タイマーの計測中はその前提が崩れるため、5.11 の定期 ping で補っている。

コストは常駐するゲスト数がおよそ倍になることだが、ゲスト1件は約15.8 KB（7.3 参照）であり、到着200件/時という非現実的な想定でも3MB程度にとどまる。削除のクエリ数も件数によらず8で変わらない。

#### リクエスト駆動にした理由

本番に Solid Queue のワーカーが存在しない（3.3）。選択肢は Render の Cron Job サービス追加、`SOLID_QUEUE_IN_PUMA` の有効化、リクエスト駆動の3つだった。

`SOLID_QUEUE_IN_PUMA` を有効化すると、worker が 0.1 秒間隔、dispatcher が 1 秒間隔でポーリングを始める。`config/database.yml` の production では `queue` / `cache` / `cable` がいずれも `primary_production` を継承して `database:` 名だけを差し替えているため、Neon では同一エンドポイント（同一 compute）上の別データベースになる。結果として Neon の compute が24時間起き続け、無料枠の compute 時間を使い切るおそれがある。加えてパスワード再設定メールを非同期に切り替えるかという別の判断も絡む。

リクエスト駆動は追加インフラ・追加課金・Neon の常時稼働のいずれも不要で、かつ**ゲストを増やす経路と減らす経路が同一**であるため増加と削除が自動的に釣り合う。誰も使わない期間は古いゲストが残るが、残るのは行だけで害はなく、次に誰かが使った瞬間に消える。

削除ロジックをサービスオブジェクトに切り出しておくため、将来ワーカーを有効化した場合は `recurring.yml` から呼ぶ形へ数行で移せる。

### 5.7 ゲストに制限する操作

デモの目的は全機能を触ってもらうことなので、制限は4つに限定する。それ以外（光の時間の CRUD、活動記録、ポモドーロ、浄化タイマー、後悔記録、要約の闇の時間への追記）はすべて通常どおり使える。

| 操作 | 理由 |
|---|---|
| アカウント編集・更新 | `app/views/users/registrations/edit.html.erb:42` が `current_password` を必須にしている。ゲストは自分のランダムパスワードを知らないため成功しない。フォームを見せて失敗させるより、理由を出して塞ぐ |
| アカウント削除 | 画面にボタンはないが、`devise_for :users` が `DELETE /users` のルートを生成しており到達可能 |
| パスワード再設定 | ゲストのメールは架空アドレスのため届かない。`send_devise_notification` は `deliver_now` で同期送信するため、バウンス処理でリクエストが待たされるおそれもある |
| AI要約の生成 | コストと悪用余地の排除。代わりにデモ要約を事前投入する |

UI で隠すこととサーバで塞ぐことは必ず両方行う。ルートは残るため、リンクを消しただけでは防御にならない。

```ruby
# ApplicationController
# ゲストに許可しない操作の共通ガード。UI 側でもリンクを出さないが、
# ルートは残るのでサーバ側でも必ず塞ぐ。
def reject_guest
  return unless current_user&.guest?

  redirect_to mypage_path,
              alert: t("defaults.flash_message.guest_not_allowed"),
              status: :see_other
end
```

`status: :see_other` は既存の `redirect_to_not_found` に合わせる（DELETE / PATCH からの遷移で Turbo がリクエストメソッドを引き継がないようにするため）。

適用先:

- `Users::RegistrationsController` — `edit` / `update` / `destroy`
- `Users::PasswordsController` — 全体
- `RegretSummariesController` — `generate`

アカウント情報画面（`users/registrations#show`）そのものは見せる。`guest_xxxx@example.com` が表示されることで、使い捨てのデモアカウントであることが伝わる。隠すのは「編集する」ボタンのみ。

### 5.8 AI要約の見せ方

`app/views/regret_summaries/_regret_summary.html.erb`（`regret_records/index.html.erb:20` から1回 render されるのみ）で、ゲストには生成ボタンの代わりに理由を表示する。

事前投入したデモ要約は表示されるため、要約の見た目は確認できる。また「闇の時間の特徴へ追記」（`append_to_dark_time`）は OpenAI を呼ばないため、そのまま動作する。連携の挙動は体験できる。

**事前生成した要約には「デモ用のサンプルです」と明記する。** これを書かないと、閲覧者に「いま生成された」と誤解させることになる。

### 5.9 ゲスト表示

**専用のバッジは置かない。** ゲストであることは既存の UI で示す。

- マイページ右上のユーザーカード: 名前が「ゲストユーザー」、ログアウトボタンが「ゲストを終了」
- アカウント情報画面: メールアドレスが `guest_xxxx@example.com` と表示され、使い捨てであることが伝わる

#### 全画面固定バッジを試して取りやめた経緯

当初の決定11は「全画面で常に見えるバッジ」だった。実装して実機で確認した結果、**3つの配置を試して3つとも別の要素に衝突した**ため取りやめている。同じ失敗を繰り返さないよう記録する。

| 配置 | 衝突した相手 |
|---|---|
| 下部中央 `fixed` | マイページのポモドーロ「スタート」ボタン、後悔記録一覧のカード本文、マイステータスのグラフ。確認した全画面 |
| 左上 `top-7 left-20`（ハンバーガーの右隣） | `dark_times/show` など5画面の「← マイページに戻る」（約200px まで） |
| 左上 `top-7 left-56` | スマホ幅でマイページ右上のカード群。`w-30`×2 + `gap-3` = 252px が右寄せで、375px 幅では x=99〜351px を占めるため、バッジ（224〜312px）が完全に重なる |

原因は共通していて、**このアプリは全画面が背景画像＋浮いたカードの密なレイアウトで、四隅がすべて何かに使われている**こと。固定オーバーレイを全画面・全幅で衝突なく置き続けるコストが、得られる情報量に見合わない。

加えて、マイページではユーザーカードが「ゲストユーザー」「ゲストを終了」と表示しているため、バッジは冗長だった（3番目の配置では、その表示自体を覆っていた）。

バッジが情報を足していたのはユーザーカードが無い画面（活動記録一覧・マイステータス・後悔記録一覧・各フォーム）のみで、そこでの価値と引き換えに全画面での衝突リスクを負う判断にはならなかった。

将来もう一度「常に見える表示」が必要になった場合、衝突しえない置き場所は `_hamburger_menu` のパネル内（主要4画面、開いたときのみ表示）。

登録リンクを置かない理由は 9.1 に記載する。

### 5.10 ログアウトと時間切れの案内

ゲストのログアウトも通常のログアウトと同じくログイン画面へ戻す。ボタンの文言だけ「ゲストを終了」に変える。

**当初はトップページ（`root_path`）へ戻していたが、取りやめた。** `static_pages/home.html.erb` のヘッダーが `fixed top-0 w-full z-50` で画面最上部に貼り付くのに対し、フラッシュは `layouts/application.html.erb` の `<body>` 直下にある通常フローの要素なので、ヘッダーがフラッシュを覆い隠す。結果として「ログアウトしました。」が読めなかった。

固定ヘッダーを持つのはホーム画面だけで、ログイン画面には無いため、戻り先を変えるだけで解決する。ログイン画面には「ゲストとして試す」ボタンがあるので、やり直しの導線も保たれる。同じ理由で、レート制限超過時の戻り先もログイン画面にしている。

この不具合は request spec では捕まらない（リダイレクト先しか見ない）。また System Spec の `have_content` でも捕まらない。フラッシュは覆われていても DOM には存在し、`spec/support/capybara.rb` が `Capybara.ignore_hidden_elements = false` を設定しているため見つかってしまう。Capybara は z-index による重なりを判定できないので、`have_no_css("nav.fixed")` で「覆う要素が無い画面か」を直接確かめている。

時間切れで削除されたゲストが再び操作した場合、Devise はセッションが参照する User を見つけられず「未ログイン」として扱い、既定の `devise.failure.unauthenticated`（「ログインもしくはアカウント登録してください。」）を表示する。これでは理由が伝わらないため、専用の案内に差し替える。

```ruby
class Users::SessionsController < Devise::SessionsController
  def new
    # ゲストのセッションが張られていたのにユーザーが居ない = 利用時間切れで削除された後。
    # Devise の既定文言では理由が伝わらないため、ゲスト向けの説明に差し替える。
    flash.now[:alert] = t("users.sessions.guest_expired") if session.delete(:guest_sign_in)
    super
  end
end
```

カスタムの `Devise::FailureApp` は作らない。認証失敗を全面的に差し替えることになり影響範囲が広すぎる。上の方法なら10行程度で、既存の認証フローに手を入れない。

通常のログアウトでは誤爆しない。`Devise.sign_out_all_scopes` が既定で true のため、ログアウト時に Warden がセッション全体をリセットし、印も一緒に消える。

遷移先はログイン画面のままとする。決定12によりゲストログインのボタンがログイン画面にも置かれるため、案内と再開ボタンが同じ画面に並ぶ。

## 6. Google 認証との関係

影響しない。

`User.from_omniauth` は `current_user` を参照せず、`provider`/`uid` で探し、無ければメールアドレスで探す。ゲストのメールは `guest_<16桁hex>@example.com` のため、Google アカウントのメールと一致することはない。既存ユーザーの誤マッチは起きない。

ゲストがログイン中に Google 認証を通った場合は、その Google アカウントの実ユーザーとしてログインし直され、ゲストのレコードは取り残される。1時間後に削除対象になるだけで害はない。Devise の `already_authenticated` があるため、ログイン中のゲストがログイン画面に辿り着くこと自体が通常ない。

`sign_in(user)` では remember me クッキーは発行されない。明示的に `remember_me` を呼ばない限り、ゲストのセッションは通常のブラウザセッションで完結する。

## 7. 実測値

すべて開発コンテナ（Docker 上の PostgreSQL）で計測。ネットワーク越しの Neon では往復時間が加算されるため、7.2 の注記を参照。

### 7.1 ゲスト1件の生成コスト（5回平均）

```
合計                      : 256.7 ms  （最大 277.8 ms）
  ├ bcrypt ハッシュ化      : 211.9 ms  ← 全体の 83%
  ├ 活動記録 40件 insert_all:  19.8 ms
  └ 後悔記録 20件 insert_all:   4.2 ms
```

支配的なのは `Devise.stretches = 12` の bcrypt であり、これは通常の新規登録でも毎回払っているコスト。デモデータ60件の投入は合計24msで実質無視できる。

なお計測時のデータ量（活動記録40件・後悔記録20件）は 5.4 で定めた構成（30〜40件・8〜10件）より多いため、この値は上限として読める。

### 7.2 削除コスト（ゲスト100件 = 6,600行）

```
方式A: user.destroy! を1件ずつ  : 5,652 ms /  7,402 クエリ（1件あたり 56.5ms、74クエリ）
方式B: 一括 delete_all          :    17 ms /      8 クエリ（件数によらず一定）
```

ローカルの1クエリ往復は 0.327 ms であり、方式Aの 5,652ms のうち約 2,420ms（43%）は往復オーバーヘッドである。したがって Neon 相手では往復回数が支配的になる。

```
往復  2ms の場合 : 7,402 × 2ms  ≒  15 秒（100件あたり）
往復 20ms の場合 : 7,402 × 20ms ≒ 148 秒（100件あたり）
```

方式Bは8クエリ固定のため、往復50msでも0.4秒に収まる。方式Bを採用する根拠。

### 7.3 ゲスト1件のディスク使用量

現実的な日本語のデモデータ（活動記録40件・後悔記録10件・要約1件を含む）で 15.8 KB。

```
到着  10件/時 → 猶予30分:  79 KB 常駐  /  猶予60分: 158 KB 常駐
到着  50件/時 → 猶予30分: 394 KB 常駐  /  猶予60分: 788 KB 常駐
到着 200件/時 → 猶予30分: 1.5 MB 常駐  /  猶予60分: 3.1 MB 常駐
```

## 8. テスト方針

- `spec/services/guest_user_builder_spec.rb` — 生成物が不変条件を満たすこと。`is_current` がちょうど1件、5段階評価が全件 1..5、`desired_self_percentage` が計算済み（`insert_all` でコールバックを飛ばすため）、`last_request_at` が入っていること、**今日付けの活動記録が0件であること**
- `spec/services/guest_user_purger_spec.rb` — 1時間無操作のゲストだけが消え、実ユーザーと操作中のゲストは残ること。`freeze_time` / `travel_to` はグローバルに include 済み
- `spec/requests/guest_sessions_spec.rb` — ゲストログインが成功すること、レート制限が効くこと
- `spec/requests/` — ゲストが `registrations#edit/update/destroy`、`passwords`、`regret_summaries#generate` でリダイレクトされること。UI を隠すだけでは不十分な部分なので、request spec で直接叩いて確認する
- `spec/system/guests_spec.rb` — ボタンからログインしてデモが表示されること、バッジが出ること、AI要約の生成ボタンが出ないこと

**必須のテスト**: デモデータ投入直後に活動記録を1件作ったとき、浄化タイマーの付与がその1件ぶんだけであること。5.4 で扱った台帳の抜け穴を塞げているかの検証であり、これがないと後からデモデータの日付を変えたときに静かに壊れる。

`spec/factories/users.rb` に `guest` trait を追加する。

## 9. 対象外とした選択肢とその理由

### 9.1 実ユーザーの「お試し」を兼ねる

このアプリが書かせるのは「本来望んでいる行動」「なりたい自分」「ついやってしまう行動」「後悔した1日」という極めて個人的な内容である。他人のデモデータが入った状態で始まると、

- 自分ごとにならない（お試しの目的は「自分が使う姿を想像すること」なのに、想像の対象が他人の記録になる）
- 使い始めるのにまずデモデータを消す作業が要る（`LightTime` の削除は `destroy_with_current_reassignment!` を通る設計であり、閲覧者に触らせる操作としては重い）
- お試しで書いたデータが削除により失われる

加えて、Google OmniAuth が入っているため実ユーザーは1クリックで本登録できる。「登録が面倒だからゲストで試したい」という課題自体が強くない。

兼ねようとするとデモデータのリセット機能・本登録への引き継ぎ・削除前の警告が必要になり、作るものが2〜3倍になる。

同じ理由から、バッジに登録導線のリンクも置かない。リンクがあると閲覧者は「続きから使える」と期待するが、押しても空のアカウントができるだけであり、期待を裏切ることになる。

### 9.2 共有の1アカウント

`guest@example.com` を1件だけ用意して全員で使う方式は、以下の破綻を起こす。

1. **閲覧者Aが浄化タイマーを回すと、閲覧者Bはポモドーロを開始できない。** `ActivityRecordsController#ensure_purification_not_counting`（`app/controllers/activity_records_controller.rb:87`）がサーバ側で `current_user.purification_time&.counting?` を見て追い返す。`purification_times` は `user_id` に unique 制約のある1行のため、共有アカウントではAとBの浄化タイマーが同一レコードになる。このガードは同一ユーザーの別タブを想定した設計であり、共有アカウントでは別人に対して発動する
2. **閲覧者Bが浄化タイマーをリセットすると、Aの計測中タイマーが消える。** `reset!` は無条件に `remaining_time: 0, status: :idle` を書く
3. **閲覧者Aが光の時間を切り替えると、Bのマイページの光の時間も入れ替わる。** `LightTime.switch_current!` は `where.not(id:).update_all(is_current: false)` でユーザー単位に一括更新する
4. **デモが徐々に壊れる。** 閲覧者が書いた記録が溜まり、光の時間を削除されれば前提も崩れる。定期リセットの間隔をどれだけ短くしても、壊れたデモを見せている時間帯が生まれる

使い捨て方式の生成コストは 0.25 秒（うち83%は通常の新規登録でも払う bcrypt）であり、上記の破綻を受け入れる理由にならない。

### 9.3 AI要約をゲストにも実行させる

`RegretSummarizer` は `MAX_RECORDS = 30` × `MAX_CHARS_PER_RECORD = 300` で最大9,000文字を `gpt-4o-mini` に渡す。1回あたりのコストは小さいが、ゲストは使い捨てのためユーザー単位の `rate_limit`（`by: current_user.id`）が事実上機能しない。

デモ要約を事前投入すれば、要約の見た目と「闇の時間へ追記」フローは体験でき、API コストと悪用余地はゼロになる。

### 9.4 ログアウト時に即削除する

閲覧者はログアウトせずにタブを閉じるのが通常であり、ログアウト時削除だけでは成立しない。リクエスト駆動の削除はどちらにせよ必要になるため、削除経路を2つ持つ価値が小さい。得られるのは「数時間早く消える」ことだけで、1件約15.8 KB の規模では見合わない。

## 10. 既知の制約

- **Turbo Frame / Turbo Stream 経由の操作では時間切れの案内が表示されない。** AI要約の生成ボタン（`turbo_frame_tag "regret_summary"` 内）やお気に入りのトグル（`favorite.turbo_stream.erb`）から操作した場合、ログイン画面へのリダイレクトがフレームに吸われ、Turbo の「Content missing」が表示される。猶予を1時間とし操作中のゲストを除外する設計により発生頻度は低いが、完全には防げない。フレーム側の例外処理を全面的に追加するコストに見合わないため、制約として受け入れる
- **誰もゲストログインを使わない期間は、古いゲストが DB に残る。** リクエスト駆動の削除であるため。残るのは行だけで害はなく、次に誰かが使った瞬間に削除される
- **`config/recurring.yml` の既存ジョブ（`clear_solid_queue_finished_jobs`）も本番では動いていない。** 本設計の対象外だが、別途対処が必要な既知の事実として記録する
- **レート制限は `CF-Connecting-IP` で数える（#287 で対処済み）。** `request.remote_ip` は使えない。本番調査の結果、`X-Forwarded-For` は `[実クライアント, Cloudflare のエッジ, Render 内部（プライベート）]` の3段で、Rails は右端の非プライベート = **Cloudflare のエッジ IP** を採っていた（②の持ち主は ipinfo で `AS13335 Cloudflare, Inc.` と確認）。エッジ IP は訪問者ごとではなく地域ごとなので、同じ地域の訪問者が全員ひとつの枠を共有し、20回/時間が事実上の全体上限になっていた。

  `CF-Connecting-IP` は Cloudflare が付ける実クライアント IP で、クライアントが送ってきた同名ヘッダは Cloudflare が上書きするため、Cloudflare を通る限り偽装できない。`trusted_proxies` に Cloudflare の IP 範囲を設定する案は、範囲の一覧を自前で持ち続けることになり Cloudflare 側の変更で静かに壊れるため採らなかった。

  **残る限界**: Render のオリジンへ直接アクセスできる場合、Cloudflare を迂回してこのヘッダを自分で付けられる。ただし対処前は枠が全員共有で何も守れていなかったため悪化はしない。レート制限はセキュリティ境界ではなく濫用の緩和と位置づける。

  参考として、`actionpack-8.1.3.1` の `RemoteIp#calculate_ip` は `X-Forwarded-For` を `reverse!` してから最初の非信頼 IP を採る（**右端優先**。プライベート範囲は既定の信頼リストに入る）。実測:

  | X-Forwarded-For | `remote_ip` |
  |---|---|
  | `1.2.3.4`（偽装のみ、プロキシが追記しない） | `1.2.3.4` |
  | `1.2.3.4, 203.0.113.9`（追記する） | `203.0.113.9` |
  | `1.2.3.4, 203.0.113.9, 10.0.0.9` | `203.0.113.9` |
  | `203.0.113.9, 198.51.100.7`（手前に公開IPのプロキシ） | `198.51.100.7` |

  この表の最終行が、まさに本番で起きていた状況にあたる。対処後は本番で `CF-Connecting-IP` が届いており、レート制限が実クライアント IP 単位で数えられていることを確認済み（確認に使った一時的な診断ログは削除した）
- **`guest_heartbeat_controller.js` の挙動はテストで覆えていない。** このリポジトリに JS のテスト基盤が無いため、`setInterval` の発火や `held()` による分岐は自動テストの対象外。エンドポイント・CSRF・要素の出し分けは request spec で固めてある
