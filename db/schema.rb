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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_100100) do
  create_table "evaluations", force: :cascade do |t|
    t.integer "story_id", null: false
    t.integer "profile_id", null: false
    t.string "status", null: false
    t.string "note"
    t.float "similarity"
    t.integer "llm_score"
    t.integer "score"
    t.json "reasons", default: [], null: false
    t.json "tags", default: [], null: false
    t.string "should_read"
    t.string "model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id"], name: "index_evaluations_on_profile_id"
    t.index ["story_id", "profile_id"], name: "index_evaluations_on_story_id_and_profile_id", unique: true
    t.index ["story_id"], name: "index_evaluations_on_story_id"
  end

  create_table "feedbacks", force: :cascade do |t|
    t.integer "story_id", null: false
    t.integer "rating"
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id"], name: "index_feedbacks_on_story_id", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.integer "version", null: false
    t.text "description", null: false
    t.json "tag_weights", default: {}, null: false
    t.json "excluded_domains", default: [], null: false
    t.json "excluded_keywords", default: [], null: false
    t.integer "score_threshold", default: 5, null: false
    t.binary "embedding"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["version"], name: "index_profiles_on_version", unique: true
  end

  create_table "stories", force: :cascade do |t|
    t.integer "hn_id", null: false
    t.string "title", null: false
    t.string "url"
    t.string "author"
    t.integer "points", default: 0, null: false
    t.integer "num_comments", default: 0, null: false
    t.datetime "posted_at"
    t.text "story_text"
    t.text "content"
    t.string "content_status", default: "pending", null: false
    t.integer "fetch_attempts", default: 0, null: false
    t.datetime "retry_after"
    t.string "fetch_error"
    t.json "comments", default: [], null: false
    t.binary "embedding"
    t.date "digested_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["digested_on"], name: "index_stories_on_digested_on"
    t.index ["hn_id"], name: "index_stories_on_hn_id", unique: true
  end

  create_table "summaries", force: :cascade do |t|
    t.integer "story_id", null: false
    t.json "key_points", default: [], null: false
    t.text "relevance"
    t.text "discussion"
    t.text "verdict"
    t.string "model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id"], name: "index_summaries_on_story_id", unique: true
  end

  create_table "translations", force: :cascade do |t|
    t.integer "story_id", null: false
    t.json "segments", default: [], null: false
    t.string "status", default: "running", null: false
    t.string "model"
    t.string "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id"], name: "index_translations_on_story_id", unique: true
  end

  add_foreign_key "evaluations", "profiles"
  add_foreign_key "evaluations", "stories"
  add_foreign_key "feedbacks", "stories"
  add_foreign_key "summaries", "stories"
  add_foreign_key "translations", "stories"
end
