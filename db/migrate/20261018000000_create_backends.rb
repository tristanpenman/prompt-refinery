class CreateBackends < ActiveRecord::Migration[8.1]
  class MigrationBackend < ActiveRecord::Base
    self.table_name = "backends"
  end

  def up
    create_table :backends do |t|
      t.string :name, null: false
      t.string :base_url, null: false
      t.string :adapter, null: false, default: "ollama"
      t.boolean :enabled, null: false, default: true
      t.boolean :system, null: false, default: false

      t.timestamps
    end

    add_index :backends, :name, unique: true
    add_index :backends, :system, unique: true, where: "system = 1"
    add_check_constraint :backends, "adapter IN ('ollama')", name: "backends_adapter_check"
    add_check_constraint :backends, "NOT system OR enabled", name: "backends_system_enabled_check"

    MigrationBackend.create!(
      name: "Local Ollama",
      base_url: normalized_ollama_url,
      adapter: "ollama",
      enabled: true,
      system: true
    )
  end

  def down
    drop_table :backends
  end

  private

  def normalized_ollama_url
    ENV.fetch("OLLAMA_URL", "http://ollama:11434").strip.sub(%r{/+\z}, "")
  end
end
