class AddInferenceAdapterSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :trials, :backend_adapter, :string, null: false, default: "ollama"
    %w[student teacher].each do |role|
      add_column :prompt_refinements, "#{role}_backend_adapter", :string, null: false, default: "ollama"
    end
    add_check_constraint :backends, "system = 0 OR adapter = 'ollama'", name: "backends_system_adapter_check"
  end
end
