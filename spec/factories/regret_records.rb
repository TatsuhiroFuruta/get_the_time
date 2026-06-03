FactoryBot.define do
  factory :regret_record do
    title { "ダラダラ過ごしてしまった日" }
    content { "やるべきことに手をつけられず、一日中スマホを触ってしまった。" }

    association :user
  end
end
