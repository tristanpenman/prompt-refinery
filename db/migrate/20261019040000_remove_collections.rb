class RemoveCollections < ActiveRecord::Migration[8.1]
  def up
    # Prompts are now standalone and archived rather than soft-deleted.
    remove_index :prompts, :deleted_at
    rename_column :prompts, :deleted_at, :archived_at
    add_index :prompts, :archived_at

    remove_index :prompts, [ :collection_id, :position ]
    remove_column :prompts, :position
    remove_reference :prompts, :collection, foreign_key: true, index: true

    drop_table :collection_revision_prompts
    drop_table :collection_revisions
    drop_table :collections
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Collections and their revisions cannot be restored"
  end
end
