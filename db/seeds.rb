# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
user = User.first || User.create!(
  email: "test@example.com",
  password: "password"
)

# LightTime作成
light_time = user.light_times.first || user.light_times.create!(
  action: "読書",
  is_current: true,
  characteristic: "集中できる"
)

# DarkTime作成
dark_time = user.dark_time || user.create_dark_time!(
  behavior: "ついついスマホを見てしまう",
  characteristic: "疲れやすい"
)

# ActivityRecordを30件作成
40.times do
  total_duration = rand(10..120)
  idle_duration = rand(0..total_duration)

  start_time = Faker::Time.backward(days: 5)
  end_time = start_time + total_duration.minutes

  user.activity_records.create!(
    started_at: start_time,
    ended_at: end_time,
    task: Faker::Lorem.sentence(word_count: 3),
    total_duration: total_duration,
    idle_duration: idle_duration,
    satisfaction: rand(1..5),
    progress: rand(1..5),
    quality: rand(1..5),
    focus: rand(1..5),
    fatigue: rand(1..5),
    comment: Faker::Lorem.sentence,
    light_time: light_time
  )
end
