class CreateLanguageModelFamilies < ActiveRecord::Migration[8.1]
  def change
    create_table :language_model_families do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :language_model_families, :name, unique: true
  end
end
