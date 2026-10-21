class CreatePromptRefinementIterations < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_refinement_iterations do |table|
      table.references :refinement, null: false, foreign_key: { to_table: :prompt_refinements }
      table.integer :number, null: false
      table.references :prompt_revision, null: false, foreign_key: true
      # Created when the iteration's trial starts.
      table.references :student_trial, foreign_key: { to_table: :trials }, index: { unique: true }
      table.string :status, null: false, default: "pending"

      table.text :evaluation_prompt
      table.text :evaluation_response
      table.json :case_evaluations, null: false, default: {}
      table.decimal :agreement, precision: 4, scale: 3
      table.text :summary
      table.text :change_summary
      table.text :proposed_template
      table.text :error

      table.datetime :started_at
      table.datetime :completed_at

      table.timestamps
    end

    add_index :prompt_refinement_iterations, [ :refinement_id, :number ], unique: true
    add_check_constraint :prompt_refinement_iterations,
      "status IN ('pending', 'running_trial', 'evaluating', 'completed', 'failed')",
      name: "prompt_refinement_iterations_status_check"
    add_check_constraint :prompt_refinement_iterations,
      "agreement IS NULL OR agreement BETWEEN 0 AND 1",
      name: "prompt_refinement_iterations_agreement_check"
  end
end
