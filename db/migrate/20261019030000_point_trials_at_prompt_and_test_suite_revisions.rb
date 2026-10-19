class PointTrialsAtPromptAndTestSuiteRevisions < ActiveRecord::Migration[8.1]
  def change
    # Existing trials ran whole collections and cannot be expressed as a prompt
    # revision run against a test suite revision, so they are discarded.
    reversible do |direction|
      direction.up do
        execute "DELETE FROM responses"
        execute "DELETE FROM trials"
      end
    end

    remove_index :responses, [ :trial_id, :prompt_id ], unique: true
    remove_index :responses,
      [ :trial_id, :collection_revision_prompt_id ],
      unique: true,
      name: "index_responses_on_trial_and_revision_prompt"
    remove_reference :responses, :prompt, null: false, foreign_key: true, index: true
    remove_reference :responses, :collection_revision_prompt, null: false, foreign_key: true, index: true
    add_reference :responses, :test_suite_revision_case, null: false, foreign_key: true
    add_index :responses,
      [ :trial_id, :test_suite_revision_case_id ],
      unique: true,
      name: "index_responses_on_trial_and_revision_case"

    remove_reference :trials, :collection, null: false, foreign_key: true, index: true
    remove_reference :trials, :collection_revision, null: false, foreign_key: true, index: true
    add_reference :trials, :prompt_revision, null: false, foreign_key: true
    add_reference :trials, :test_suite_revision, null: false, foreign_key: true
  end
end
