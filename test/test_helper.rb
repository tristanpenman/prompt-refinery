ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def with_aws_region(region)
      previous_region = ENV["AWS_REGION"]
      ENV["AWS_REGION"] = region
      yield
    ensure
      ENV["AWS_REGION"] = previous_region
    end

    def create_trial(prompt: create_prompt, test_suite: create_test_suite, backend: Backend.ensure_system_default!, model: "gemma3:4b", **attributes)
      Trial.create_for!(prompt: prompt, test_suite: test_suite, backend: backend, model: model, **attributes)
    end

    def create_prompt(name: "Explain", template: "Explain {{topic}}")
      Prompt.create!(name: name, template: template)
    end

    def create_test_suite(name: "Topics", cases: [ { "topic" => "Ruby" } ])
      TestSuite.create!(name: name, variables: cases.first.keys).tap do |test_suite|
        cases.each_with_index { |values, position| test_suite.test_cases.create!(values: values, position: position) }
      end
    end
  end
end
