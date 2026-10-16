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

ActiveRecord::Schema[8.1].define(version: 2026_10_16_070000) do
  create_table "collections", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "prompts", force: :cascade do |t|
    t.integer "collection_id", null: false
    t.string "name", null: false
    t.text "template", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id", "position"], name: "index_prompts_on_collection_id_and_position"
    t.index ["collection_id"], name: "index_prompts_on_collection_id"
  end

  create_table "responses", force: :cascade do |t|
    t.integer "trial_id", null: false
    t.integer "prompt_id", null: false
    t.string "status", default: "pending", null: false
    t.text "content"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_id"], name: "index_responses_on_prompt_id"
    t.index ["trial_id", "prompt_id"], name: "index_responses_on_trial_id_and_prompt_id", unique: true
    t.index ["trial_id"], name: "index_responses_on_trial_id"
    t.check_constraint "status IN ('pending', 'completed', 'failed')", name: "responses_status_check"
  end

  create_table "trials", force: :cascade do |t|
    t.integer "collection_id", null: false
    t.string "model", null: false
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_trials_on_collection_id"
    t.check_constraint "status IN ('pending', 'running', 'completed', 'failed')", name: "trials_status_check"
  end

  add_foreign_key "prompts", "collections"
  add_foreign_key "responses", "prompts"
  add_foreign_key "responses", "trials"
  add_foreign_key "trials", "collections"
end
