class CreateTestSuitesAndTestCases < ActiveRecord::Migration[8.1]
  def change
    create_table :test_suites do |t|
      t.string :name, null: false
      t.json :variables, null: false, default: []
      t.datetime :archived_at

      t.timestamps
    end

    add_index :test_suites, :archived_at

    create_table :test_cases do |t|
      t.references :test_suite, null: false, foreign_key: true
      t.json :values, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :test_cases, [ :test_suite_id, :position ]
    add_index :test_cases, :deleted_at
  end
end
