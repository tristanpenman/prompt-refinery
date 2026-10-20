namespace :prompt_refinery do
  namespace :demo do
    # Children before parents, so foreign keys hold at every step.
    DEMO_RESET_MODELS = %w[
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

    desc "Delete all prompts, test suites, trials, and backends, then load db/seeds/demo.rb (set CONFIRM=1 to skip the prompt)"
    task reset: [ "db:check_protected_environments", :environment ] do
      unless ENV["CONFIRM"] == "1"
        print "This deletes all data in the #{Rails.env} database. Type 'yes' to continue: "
        abort "Aborted" unless $stdin.gets.to_s.strip == "yes"
      end

      ActiveRecord::Base.transaction do
        models = DEMO_RESET_MODELS.map(&:constantize)
        models.each(&:delete_all)

        # Restart ids at 1 so demo URLs are predictable.
        tables = models.map { |model| ActiveRecord::Base.connection.quote(model.table_name) }
        ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence WHERE name IN (#{tables.join(", ")})")

        load Rails.root.join("db/seeds.rb")
        load Rails.root.join("db/seeds/demo.rb")
      end

      puts "Loaded demo data: #{Prompt.count} prompts, #{TestSuite.count} test suites, #{Trial.count} trials"
    end
  end
end
