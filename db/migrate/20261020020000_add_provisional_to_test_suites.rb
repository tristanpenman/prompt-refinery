class AddProvisionalToTestSuites < ActiveRecord::Migration[8.1]
  def change
    # Suites created by a CSV import stay provisional until the preview is confirmed.
    add_column :test_suites, :provisional, :boolean, null: false, default: false
    add_index :test_suites, :provisional
  end
end
