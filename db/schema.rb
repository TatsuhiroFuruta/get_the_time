# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_31_074958) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activity_records", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.decimal "desired_self_percentage", precision: 5, scale: 2
    t.datetime "ended_at"
    t.integer "fatigue"
    t.integer "focus"
    t.integer "idle_duration"
    t.bigint "light_time_id", null: false
    t.integer "progress"
    t.integer "quality"
    t.integer "satisfaction"
    t.datetime "started_at"
    t.text "task"
    t.integer "total_duration"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["light_time_id"], name: "index_activity_records_on_light_time_id"
    t.index ["user_id"], name: "index_activity_records_on_user_id"
  end

  create_table "dark_times", force: :cascade do |t|
    t.text "behavior", null: false
    t.text "characteristic"
    t.datetime "created_at", null: false
    t.text "unwanted_future"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_dark_times_on_user_id", unique: true
  end

  create_table "light_times", force: :cascade do |t|
    t.text "action", null: false
    t.text "characteristic"
    t.datetime "created_at", null: false
    t.text "desired_self"
    t.boolean "is_current", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_light_times_on_user_id"
  end

  create_table "purification_times", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "paused_at"
    t.integer "remaining_time", default: 0, null: false
    t.datetime "started_at"
    t.integer "status"
    t.integer "total_time", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_purification_times_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "activity_records", "light_times"
  add_foreign_key "activity_records", "users"
  add_foreign_key "dark_times", "users"
  add_foreign_key "light_times", "users"
  add_foreign_key "purification_times", "users"
end
