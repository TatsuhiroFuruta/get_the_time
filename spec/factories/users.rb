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
