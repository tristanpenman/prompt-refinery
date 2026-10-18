class AddBackendToTrials < ActiveRecord::Migration[8.1]
  class MigrationBackend < ActiveRecord::Base
    self.table_name = "backends"
  end

  class MigrationTrial < ActiveRecord::Base
    self.table_name = "trials"
  end

  def up
    add_reference :trials, :backend, foreign_key: true
    add_column :trials, :backend_name, :string
    add_column :trials, :backend_base_url, :string

    backend = MigrationBackend.find_by!(system: true)
    MigrationTrial.update_all(
      backend_id: backend.id,
      backend_name: backend.name,
      backend_base_url: backend.base_url
    )

    change_column_null :trials, :backend_id, false
    change_column_null :trials, :backend_name, false
    change_column_null :trials, :backend_base_url, false
  end

  def down
    remove_reference :trials, :backend, foreign_key: true
    remove_column :trials, :backend_name
    remove_column :trials, :backend_base_url
  end
end
