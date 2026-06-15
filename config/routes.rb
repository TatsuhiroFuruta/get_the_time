Rails.application.routes.draw do
  # 送信メールをブラウザで確認する（開発環境のみ）
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  devise_for :users, controllers: {
    registrations: "users/registrations",
    sessions: "users/sessions",
    passwords: "users/passwords"
  }

  # アカウント情報画面
  devise_scope :user do
    get "users/account", to: "users/registrations#show", as: :user_account
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  # ログイン済みユーザーのルートパス
  authenticated :user do
    root "mypages#show", as: :authenticated_root # ログイン後はマイページへ遷移
  end

  # 未ログインユーザーのルートパス
  root "static_pages#home" # ホーム画面をルートパスに設定

  resource :mypage, only: %i[show]
  # マイステータス（時系列グラフ）
  resource :mystatus, only: %i[show]
  # 闇の時間の活動内容
  resource :dark_time, only: %i[new create show edit update]
  # 光の時間の活動内容
  resources :light_times, only: %i[new create show edit update destroy] do
    member do
      patch :switch   # is_current切り替え用
    end
  end
  # 光の時間の活動記録
  resources :activity_records do
    collection do
      get :pomodoro_timer    # タイマーページ
    end
    member do
      patch :favorite        # お気に入りトグル
    end
  end

  # 浄化タイマー
  resource :purification_time, only: %i[show] do
    patch :start
    patch :stop
    patch :reset
  end

  # ポモドーロタイマーの時間設定
  resource :pomodoro_setting, only: %i[update]

  # 後悔した1日の記録
  resources :regret_records do
    member do
      patch :favorite        # お気に入りトグル
    end
  end

  # 後悔した1日の記録の生成AI要約（ユーザーごと1件）
  resource :regret_summary, only: [] do
    patch :generate            # お気に入りから要約を生成（同期）
    patch :append_to_dark_time # 闇の時間の特徴へ追記
  end

  # 使い方ページ
  get "/how_to_use", to: "static_pages#how_to_use", as: "how_to_use"

  # 振り返り方ページ
  get "/reflection_guide", to: "static_pages#reflection_guide", as: "reflection_guide"
end
