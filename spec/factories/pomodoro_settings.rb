FactoryBot.define do
  # User の after_create で自動生成されるため、create(:pomodoro_setting) は
  # 一意制約に抵触する。バリデーションの単体検証は build で利用し、
  # 永続化済みの設定が必要なときは user.pomodoro_setting を直接参照する。
  factory :pomodoro_setting do
    work_duration { 25 }
    break_duration { 5 }
    association :user
  end
end
