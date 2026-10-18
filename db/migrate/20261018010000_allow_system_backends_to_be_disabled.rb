class AllowSystemBackendsToBeDisabled < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :backends, name: "backends_system_enabled_check"
  end
end
