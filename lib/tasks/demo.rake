namespace :prompt_refinery do
  namespace :demo do
    # Children before parents, so foreign keys hold at every step.
    DEMO_RESET_MODELS = %w[
      ActiveStorage::VariantRecord
      ActiveStorage::Attachment
      ActiveStorage::Blob
      PromptRefinementIteration
      PromptRefinement
      Response
      Trial
      TestSuiteRevisionCase
      TestCaseRevision
      TestSuiteRevision
      TestCase
      TestSuite
      PromptRevision
      Prompt
      LanguageModel
      LanguageModelFamily
      Backend
    ].freeze

    desc "Delete all prompts, test suites, trials, backends, and uploaded files, then load db/seeds/demo.rb (set CONFIRM=1 to skip the prompt)"
    task reset: [ "db:check_protected_environments", :environment ] do
      unless ENV["CONFIRM"] == "1"
        print "This deletes all data in the #{Rails.env} database. Type 'yes' to continue: "
        abort "Aborted" unless $stdin.gets.to_s.strip == "yes"
      end

      # Rows are deleted directly, so stored files are removed once the transaction commits.
      blob_keys = ActiveStorage::Blob.pluck(:key)

      ActiveRecord::Base.transaction do
        models = DEMO_RESET_MODELS.map(&:constantize)
        models.each(&:delete_all)

        # Restart ids at 1 so demo URLs are predictable.
        tables = models.map { |model| ActiveRecord::Base.connection.quote(model.table_name) }
        ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence WHERE name IN (#{tables.join(", ")})")

        load Rails.root.join("db/seeds.rb")
        load Rails.root.join("db/seeds/demo.rb")
      end

      blob_keys.each { |key| ActiveStorage::Blob.service.delete(key) }

      puts "Loaded demo data: #{Prompt.count} prompts, #{TestSuite.count} test suites, #{Trial.count} trials"
    end
  end
end
