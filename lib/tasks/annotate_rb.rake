# This rake task was added by the annotaterb gem.

# Set ANNOTATERB_SKIP_ON_DB_TASKS to any value to skip automatic annotation.
if Rails.env.development? && ENV["ANNOTATERB_SKIP_ON_DB_TASKS"].nil?
  require "annotate_rb"

  AnnotateRb::Core.load_rake_tasks
end
