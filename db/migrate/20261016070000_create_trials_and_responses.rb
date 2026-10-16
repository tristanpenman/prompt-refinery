class CreateTrialsAndResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :trials do |table|
      table.references :collection, null: false, foreign_key: true
      table.string :model, null: false
      table.string :status, null: false, default: "pending"
      table.datetime :started_at
      table.datetime :completed_at

      table.timestamps
    end

    add_check_constraint :trials,
      "status IN ('pending', 'running', 'completed', 'failed')",
      name: "trials_status_check"

    create_table :responses do |table|
      table.references :trial, null: false, foreign_key: true
      table.references :prompt, null: false, foreign_key: true
      table.string :status, null: false, default: "pending"
      table.text :content
      table.text :error

      table.timestamps
    end

    add_index :responses, [ :trial_id, :prompt_id ], unique: true
    add_check_constraint :responses,
      "status IN ('pending', 'completed', 'failed')",
      name: "responses_status_check"
  end
end
