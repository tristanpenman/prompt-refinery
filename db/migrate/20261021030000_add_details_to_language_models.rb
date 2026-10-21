class AddDetailsToLanguageModels < ActiveRecord::Migration[8.1]
  def change
    # Recorded from the backend when models are refreshed, so the models page
    # can list them without contacting every backend.
    add_column :language_models, :size, :bigint
    add_column :language_models, :details, :json, null: false, default: {}
  end
end
