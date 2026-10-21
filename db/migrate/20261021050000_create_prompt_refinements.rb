class CreatePromptRefinements < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_refinements do |table|
      table.string :name, null: false
      # The working prompt the refinement writes its revisions to.
      table.references :prompt, null: false, foreign_key: true, index: { unique: true }
      table.references :starting_prompt_revision, null: false, foreign_key: { to_table: :prompt_revisions }
      table.references :test_suite_revision, null: false, foreign_key: true

      table.references :student_backend, null: false, foreign_key: { to_table: :backends }
      table.string :student_model, null: false
      table.string :student_backend_name, null: false
      table.string :student_backend_base_url, null: false
      table.references :teacher_backend, null: false, foreign_key: { to_table: :backends }
      table.string :teacher_model, null: false
      table.string :teacher_backend_name, null: false
      table.string :teacher_backend_base_url, null: false

      # Created when the refinement starts running.
      table.references :reference_trial, foreign_key: { to_table: :trials }, index: { unique: true }

      table.text :instructions, null: false
      table.integer :max_iterations, null: false, default: 3
      table.decimal :target_agreement, precision: 4, scale: 3, null: false, default: 1
      table.integer :context_size, null: false, default: 16_384

      table.string :status, null: false, default: "pending"
      table.string :stop_reason
      table.datetime :stop_requested_at
      table.datetime :started_at
      table.datetime :completed_at

      table.timestamps
    end

    add_check_constraint :prompt_refinements,
      "status IN ('pending', 'running', 'completed', 'stopped', 'failed')",
      name: "prompt_refinements_status_check"
    add_check_constraint :prompt_refinements,
      "stop_reason IS NULL OR stop_reason IN ('max_iterations', 'target_reached', 'converged', 'cancelled', 'failed')",
      name: "prompt_refinements_stop_reason_check"
    add_check_constraint :prompt_refinements,
      "max_iterations BETWEEN 1 AND 10",
      name: "prompt_refinements_max_iterations_check"
    add_check_constraint :prompt_refinements,
      "target_agreement BETWEEN 0 AND 1",
      name: "prompt_refinements_target_agreement_check"
  end
end
