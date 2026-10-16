class CreateCollectionsAndPrompts < ActiveRecord::Migration[8.1]
  def change
    create_table :collections do |table|
      table.string :name, null: false

      table.timestamps
    end

    create_table :prompts do |table|
      table.references :collection, null: false, foreign_key: true
      table.string :name, null: false
      table.text :template, null: false
      table.integer :position, null: false, default: 0

      table.timestamps
    end

    add_index :prompts, [ :collection_id, :position ]
  end
end
