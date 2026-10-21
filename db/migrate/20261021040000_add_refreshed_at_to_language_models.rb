class AddRefreshedAtToLanguageModels < ActiveRecord::Migration[8.1]
  def up
    # Records when a model was last seen on its backend by a refresh.
    add_column :language_models, :refreshed_at, :datetime
    execute "UPDATE language_models SET refreshed_at = updated_at"
    change_column_null :language_models, :refreshed_at, false
  end

  def down
    remove_column :language_models, :refreshed_at
  end
end
