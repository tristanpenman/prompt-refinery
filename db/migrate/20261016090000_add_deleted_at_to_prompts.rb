class AddDeletedAtToPrompts < ActiveRecord::Migration[8.1]
  def change
    add_column :prompts, :deleted_at, :datetime
    add_index :prompts, :deleted_at
  end
end
