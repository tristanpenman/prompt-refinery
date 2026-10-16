class AddArchivedAtToCollections < ActiveRecord::Migration[8.1]
  def change
    add_column :collections, :archived_at, :datetime
    add_index :collections, :archived_at
  end
end
