Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.data_source_exists?("backends")
    Backend.ensure_system_default!
  end
rescue ActiveRecord::NoDatabaseError
  # The database and table are created after initialization by database setup tasks.
end
