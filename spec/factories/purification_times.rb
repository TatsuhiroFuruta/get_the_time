FactoryBot.define do
  factory :purification_time do
    status { :idle }
    remaining_time { 0 }
    total_time { 0 }
    started_at { nil }
    paused_at { nil }

    association :user

    # 浄化タイマーが付与済みでスタート前の状態
    trait :idle_with_time do
      status { :idle }
      remaining_time { 600 } # 10分
    end

    # 実行中
    trait :running do
      status { :running }
      remaining_time { 600 }
      total_time { 600 }
      started_at { Time.current }
    end

    # 一時停止中
    trait :paused do
      status { :paused }
      remaining_time { 300 }
      total_time { 600 }
      started_at { 5.minutes.ago }
      paused_at { Time.current }
    end
  end
end
