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

ActiveRecord::Schema[8.1].define(version: 2026_10_16_100000) do
  create_table "collection_revision_prompts", force: :cascade do |t|
    t.integer "collection_revision_id", null: false
    t.integer "prompt_revision_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_revision_id", "position"], name: "index_revision_prompts_on_revision_and_position", unique: true
    t.index ["collection_revision_id", "prompt_revision_id"], name: "index_revision_prompts_on_revision_and_prompt", unique: true
    t.index ["collection_revision_id"], name: "index_collection_revision_prompts_on_collection_revision_id"
    t.index ["prompt_revision_id"], name: "index_collection_revision_prompts_on_prompt_revision_id"
  end

  create_table "collection_revisions", force: :cascade do |t|
    t.integer "collection_id", null: false
    t.integer "version", null: false
    t.string "name", null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id", "content_digest"], name: "index_collection_revisions_on_collection_id_and_content_digest", unique: true
    t.index ["collection_id", "version"], name: "index_collection_revisions_on_collection_id_and_version", unique: true
    t.index ["collection_id"], name: "index_collection_revisions_on_collection_id"
  end

  create_table "collections", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.index ["archived_at"], name: "index_collections_on_archived_at"
  end

  create_table "prompt_revisions", force: :cascade do |t|
    t.integer "prompt_id", null: false
    t.integer "version", null: false
    t.string "name", null: false
    t.text "template", null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_id", "content_digest"], name: "index_prompt_revisions_on_prompt_id_and_content_digest", unique: true
    t.index ["prompt_id", "version"], name: "index_prompt_revisions_on_prompt_id_and_version", unique: true
    t.index ["prompt_id"], name: "index_prompt_revisions_on_prompt_id"
  end

  create_table "prompts", force: :cascade do |t|
    t.integer "collection_id", null: false
    t.string "name", null: false
    t.text "template", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["collection_id", "position"], name: "index_prompts_on_collection_id_and_position"
    t.index ["collection_id"], name: "index_prompts_on_collection_id"
    t.index ["deleted_at"], name: "index_prompts_on_deleted_at"
  end

  create_table "responses", force: :cascade do |t|
    t.integer "trial_id", null: false
    t.integer "prompt_id", null: false
    t.string "status", default: "pending", null: false
    t.text "content"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "collection_revision_prompt_id", null: false
    t.text "rendered_prompt", null: false
    t.index ["collection_revision_prompt_id"], name: "index_responses_on_collection_revision_prompt_id"
    t.index ["prompt_id"], name: "index_responses_on_prompt_id"
    t.index ["trial_id", "collection_revision_prompt_id"], name: "index_responses_on_trial_and_revision_prompt", unique: true
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
    t.integer "collection_revision_id", null: false
    t.index ["collection_id"], name: "index_trials_on_collection_id"
    t.index ["collection_revision_id"], name: "index_trials_on_collection_revision_id"
    t.check_constraint "status IN ('pending', 'running', 'completed', 'failed')", name: "trials_status_check"
  end

  add_foreign_key "collection_revision_prompts", "collection_revisions"
  add_foreign_key "collection_revision_prompts", "prompt_revisions"
  add_foreign_key "collection_revisions", "collections"
  add_foreign_key "prompt_revisions", "prompts"
  add_foreign_key "prompts", "collections"
  add_foreign_key "responses", "collection_revision_prompts"
  add_foreign_key "responses", "prompts"
  add_foreign_key "responses", "trials"
  add_foreign_key "trials", "collection_revisions"
  add_foreign_key "trials", "collections"
end
