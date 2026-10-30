class AddBedrockAdapter < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :backends, name: "backends_adapter_check", expression: "adapter IN ('ollama')"
    add_check_constraint :backends, "adapter IN ('ollama', 'bedrock')", name: "backends_adapter_check"
  end
end
