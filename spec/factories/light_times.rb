FactoryBot.define do
  factory :light_time do
    action { "朝のランニング" }
    characteristic { "健康的な習慣" }
    desired_self { "健康的な自分" }
    is_current { false }

    association :user

    trait :current do
      is_current { true }
    end

    trait :with_activity_records do
      after(:create) do |light_time|
        create_list(:activity_record, 3, light_time: light_time)
      end
    end
  end
end
