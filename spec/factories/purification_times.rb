FactoryBot.define do
  factory :purification_time do
    remaining_time { 0 }

    association :user
  end
end
