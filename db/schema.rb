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

ActiveRecord::Schema[8.1].define(version: 2026_10_29_000000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "backends", force: :cascade do |t|
    t.string "name", null: false
    t.string "base_url", null: false
    t.string "adapter", default: "ollama", null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "system", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_backends_on_name", unique: true
    t.index ["system"], name: "index_backends_on_system", unique: true, where: "system = 1"
    t.check_constraint "adapter IN ('ollama', 'bedrock')", name: "backends_adapter_check"
    t.check_constraint "system = 0 OR adapter = 'ollama'", name: "backends_system_adapter_check"
  end

  create_table "language_model_families", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_language_model_families_on_name", unique: true
  end

  create_table "language_models", force: :cascade do |t|
    t.integer "backend_id", null: false
    t.integer "language_model_family_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "size"
    t.json "details", default: {}, null: false
    t.datetime "refreshed_at", null: false
    t.boolean "available", default: true, null: false
    t.index ["backend_id", "name"], name: "index_language_models_on_backend_id_and_name", unique: true
    t.index ["backend_id"], name: "index_language_models_on_backend_id"
    t.index ["language_model_family_id"], name: "index_language_models_on_language_model_family_id"
  end

  create_table "prompt_refinement_iterations", force: :cascade do |t|
    t.integer "refinement_id", null: false
    t.integer "number", null: false
    t.integer "prompt_revision_id", null: false
    t.integer "student_trial_id"
    t.string "status", default: "pending", null: false
    t.text "evaluation_prompt"
    t.text "evaluation_response"
    t.json "case_evaluations", default: {}, null: false
    t.decimal "agreement", precision: 4, scale: 3
    t.text "summary"
    t.text "change_summary"
    t.text "proposed_template"
    t.text "error"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_revision_id"], name: "index_prompt_refinement_iterations_on_prompt_revision_id"
    t.index ["refinement_id", "number"], name: "index_prompt_refinement_iterations_on_refinement_id_and_number", unique: true
    t.index ["refinement_id"], name: "index_prompt_refinement_iterations_on_refinement_id"
    t.index ["student_trial_id"], name: "index_prompt_refinement_iterations_on_student_trial_id", unique: true
    t.check_constraint "agreement IS NULL OR agreement BETWEEN 0 AND 1", name: "prompt_refinement_iterations_agreement_check"
    t.check_constraint "status IN ('pending', 'running_trial', 'evaluating', 'completed', 'failed')", name: "prompt_refinement_iterations_status_check"
  end

  create_table "prompt_refinements", force: :cascade do |t|
    t.string "name", null: false
    t.integer "prompt_id", null: false
    t.integer "starting_prompt_revision_id", null: false
    t.integer "test_suite_revision_id", null: false
    t.integer "student_backend_id", null: false
    t.string "student_model", null: false
    t.string "student_backend_name", null: false
    t.string "student_backend_base_url", null: false
    t.integer "teacher_backend_id", null: false
    t.string "teacher_model", null: false
    t.string "teacher_backend_name", null: false
    t.string "teacher_backend_base_url", null: false
    t.integer "reference_trial_id"
    t.text "instructions", null: false
    t.integer "max_iterations", default: 3, null: false
    t.decimal "target_agreement", precision: 4, scale: 3, default: "1.0", null: false
    t.integer "context_size", default: 16384, null: false
    t.string "status", default: "pending", null: false
    t.string "stop_reason"
    t.datetime "stop_requested_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "student_backend_adapter", default: "ollama", null: false
    t.string "teacher_backend_adapter", default: "ollama", null: false
    t.index ["prompt_id"], name: "index_prompt_refinements_on_prompt_id", unique: true
    t.index ["reference_trial_id"], name: "index_prompt_refinements_on_reference_trial_id", unique: true
    t.index ["starting_prompt_revision_id"], name: "index_prompt_refinements_on_starting_prompt_revision_id"
    t.index ["student_backend_id"], name: "index_prompt_refinements_on_student_backend_id"
    t.index ["teacher_backend_id"], name: "index_prompt_refinements_on_teacher_backend_id"
    t.index ["test_suite_revision_id"], name: "index_prompt_refinements_on_test_suite_revision_id"
    t.check_constraint "max_iterations BETWEEN 1 AND 10", name: "prompt_refinements_max_iterations_check"
    t.check_constraint "status IN ('pending', 'running', 'completed', 'stopped', 'failed')", name: "prompt_refinements_status_check"
    t.check_constraint "stop_reason IS NULL OR stop_reason IN ('max_iterations', 'target_reached', 'converged', 'cancelled', 'failed')", name: "prompt_refinements_stop_reason_check"
    t.check_constraint "target_agreement BETWEEN 0 AND 1", name: "prompt_refinements_target_agreement_check"
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
    t.string "name", null: false
    t.text "template", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.index ["archived_at"], name: "index_prompts_on_archived_at"
  end

  create_table "responses", force: :cascade do |t|
    t.integer "trial_id", null: false
    t.string "status", default: "pending", null: false
    t.text "content"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "rendered_prompt", null: false
    t.integer "test_suite_revision_case_id", null: false
    t.integer "prompt_eval_count"
    t.integer "eval_count"
    t.bigint "load_duration"
    t.bigint "prompt_eval_duration"
    t.bigint "eval_duration"
    t.bigint "total_duration"
    t.index ["test_suite_revision_case_id"], name: "index_responses_on_test_suite_revision_case_id"
    t.index ["trial_id", "test_suite_revision_case_id"], name: "index_responses_on_trial_and_revision_case", unique: true
    t.index ["trial_id"], name: "index_responses_on_trial_id"
    t.check_constraint "status IN ('pending', 'completed', 'failed')", name: "responses_status_check"
  end

  create_table "test_case_revisions", force: :cascade do |t|
    t.integer "test_case_id", null: false
    t.integer "version", null: false
    t.json "values", default: {}, null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["test_case_id", "content_digest"], name: "index_test_case_revisions_on_test_case_id_and_content_digest", unique: true
    t.index ["test_case_id", "version"], name: "index_test_case_revisions_on_test_case_id_and_version", unique: true
    t.index ["test_case_id"], name: "index_test_case_revisions_on_test_case_id"
  end

  create_table "test_cases", force: :cascade do |t|
    t.integer "test_suite_id", null: false
    t.json "values", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_test_cases_on_deleted_at"
    t.index ["test_suite_id", "position"], name: "index_test_cases_on_test_suite_id_and_position"
    t.index ["test_suite_id"], name: "index_test_cases_on_test_suite_id"
  end

  create_table "test_suite_revision_cases", force: :cascade do |t|
    t.integer "test_suite_revision_id", null: false
    t.integer "test_case_revision_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["test_case_revision_id"], name: "index_test_suite_revision_cases_on_test_case_revision_id"
    t.index ["test_suite_revision_id", "position"], name: "index_revision_cases_on_revision_and_position", unique: true
    t.index ["test_suite_revision_id", "test_case_revision_id"], name: "index_revision_cases_on_revision_and_case", unique: true
    t.index ["test_suite_revision_id"], name: "index_test_suite_revision_cases_on_test_suite_revision_id"
  end

  create_table "test_suite_revisions", force: :cascade do |t|
    t.integer "test_suite_id", null: false
    t.integer "version", null: false
    t.string "name", null: false
    t.json "variables", default: [], null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["test_suite_id", "content_digest"], name: "index_test_suite_revisions_on_test_suite_id_and_content_digest", unique: true
    t.index ["test_suite_id", "version"], name: "index_test_suite_revisions_on_test_suite_id_and_version", unique: true
    t.index ["test_suite_id"], name: "index_test_suite_revisions_on_test_suite_id"
  end

  create_table "test_suites", force: :cascade do |t|
    t.string "name", null: false
    t.json "variables", default: [], null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "provisional", default: false, null: false
    t.index ["archived_at"], name: "index_test_suites_on_archived_at"
    t.index ["provisional"], name: "index_test_suites_on_provisional"
  end

  create_table "trials", force: :cascade do |t|
    t.string "model", null: false
    t.string "status", default: "pending", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "backend_id", null: false
    t.string "backend_name", null: false
    t.string "backend_base_url", null: false
    t.integer "prompt_revision_id", null: false
    t.integer "test_suite_revision_id", null: false
    t.string "backend_adapter", default: "ollama", null: false
    t.index ["backend_id"], name: "index_trials_on_backend_id"
    t.index ["prompt_revision_id"], name: "index_trials_on_prompt_revision_id"
    t.index ["test_suite_revision_id"], name: "index_trials_on_test_suite_revision_id"
    t.check_constraint "status IN ('pending', 'running', 'completed', 'failed')", name: "trials_status_check"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "language_models", "backends"
  add_foreign_key "language_models", "language_model_families"
  add_foreign_key "prompt_refinement_iterations", "prompt_refinements", column: "refinement_id"
  add_foreign_key "prompt_refinement_iterations", "prompt_revisions"
  add_foreign_key "prompt_refinement_iterations", "trials", column: "student_trial_id"
  add_foreign_key "prompt_refinements", "backends", column: "student_backend_id"
  add_foreign_key "prompt_refinements", "backends", column: "teacher_backend_id"
  add_foreign_key "prompt_refinements", "prompt_revisions", column: "starting_prompt_revision_id"
  add_foreign_key "prompt_refinements", "prompts"
  add_foreign_key "prompt_refinements", "test_suite_revisions"
  add_foreign_key "prompt_refinements", "trials", column: "reference_trial_id"
  add_foreign_key "prompt_revisions", "prompts"
  add_foreign_key "responses", "test_suite_revision_cases"
  add_foreign_key "responses", "trials"
  add_foreign_key "test_case_revisions", "test_cases"
  add_foreign_key "test_cases", "test_suites"
  add_foreign_key "test_suite_revision_cases", "test_case_revisions"
  add_foreign_key "test_suite_revision_cases", "test_suite_revisions"
  add_foreign_key "test_suite_revisions", "test_suites"
  add_foreign_key "trials", "backends"
  add_foreign_key "trials", "prompt_revisions"
  add_foreign_key "trials", "test_suite_revisions"
end
