FactoryBot.define do
  factory :activity_record do
    association :user
    # light_time の is_current は false がデフォルトのため :current トレイトで明示
    association :light_time, factory: %i[light_time current]

    started_at     { 1.hour.ago }
    ended_at       { Time.current }
    total_duration { 60 }
    idle_duration  { 0 }
    satisfaction   { 3 }
    progress       { 3 }
    quality        { 3 }
    focus          { 3 }
    fatigue        { 3 }
    task           { "学習する" }
    comment        { "集中できた" }

    # 評価が最高のレコード
    trait :high_rating do
      satisfaction { 5 }
      progress     { 5 }
      quality      { 5 }
      focus        { 5 }
      fatigue      { 1 }
    end

    # 評価が最低のレコード
    trait :low_rating do
      satisfaction { 1 }
      progress     { 1 }
      quality      { 1 }
      focus        { 1 }
      fatigue      { 5 }
    end

    # 浄化タイマーが付与される長時間セッション（90分 → 3ブロック分ランダム付与）
    trait :long_session do
      total_duration { 90 }
      idle_duration  { 0 }
    end

    # 浄化タイマーが付与されない短時間セッション（20分）
    trait :short_session do
      total_duration { 20 }
      idle_duration  { 0 }
    end

    # 昨日の記録
    trait :yesterday do
      started_at  { 25.hours.ago }
      ended_at    { 24.hours.ago }
      created_at  { 1.day.ago }
    end
  end
end
