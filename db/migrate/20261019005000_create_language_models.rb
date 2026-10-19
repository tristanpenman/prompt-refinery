class CreateLanguageModels < ActiveRecord::Migration[8.1]
  def change
    create_table :language_models do |t|
      t.references :backend, null: false, foreign_key: true
      t.references :language_model_family, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :language_models, [ :backend_id, :name ], unique: true
  end
end
