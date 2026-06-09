FactoryBot.define do
  factory :regret_summary do
    content { "誘惑に流されやすく、夜更かしと動画視聴に時間を奪われる傾向がある。" }
    generated_at { Time.current }

    association :user
  end
end
