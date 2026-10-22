class AddAvailableToLanguageModels < ActiveRecord::Migration[8.1]
  def change
    # Whether the model was found on its backend by the most recent refresh.
    add_column :language_models, :available, :boolean, null: false, default: true
  end
end
