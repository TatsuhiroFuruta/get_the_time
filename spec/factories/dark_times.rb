FactoryBot.define do
  factory :dark_time do
    behavior { "夜更かししてしまう" }
    characteristic { "意志が弱い" }
    unwanted_future { "健康を損なう" }
    association :user
  end
end
