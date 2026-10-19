class AddTestSuiteAndTestCaseRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :test_suite_revisions do |t|
      t.references :test_suite, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :name, null: false
      t.json :variables, null: false, default: []
      t.string :content_digest, null: false

      t.timestamps
    end
    add_index :test_suite_revisions, [ :test_suite_id, :version ], unique: true
    add_index :test_suite_revisions, [ :test_suite_id, :content_digest ], unique: true

    create_table :test_case_revisions do |t|
      t.references :test_case, null: false, foreign_key: true
      t.integer :version, null: false
      t.json :values, null: false, default: {}
      t.string :content_digest, null: false

      t.timestamps
    end
    add_index :test_case_revisions, [ :test_case_id, :version ], unique: true
    add_index :test_case_revisions, [ :test_case_id, :content_digest ], unique: true

    create_table :test_suite_revision_cases do |t|
      t.references :test_suite_revision, null: false, foreign_key: true
      t.references :test_case_revision, null: false, foreign_key: true
      t.integer :position, null: false

      t.timestamps
    end
    add_index :test_suite_revision_cases,
      [ :test_suite_revision_id, :test_case_revision_id ],
      unique: true,
      name: "index_revision_cases_on_revision_and_case"
    add_index :test_suite_revision_cases,
      [ :test_suite_revision_id, :position ],
      unique: true,
      name: "index_revision_cases_on_revision_and_position"
  end
end
