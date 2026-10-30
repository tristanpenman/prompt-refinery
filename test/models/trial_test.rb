require "test_helper"

class TrialTest < ActiveSupport::TestCase
  setup do
    @prompt = create_prompt(template: "Explain {{topic}} to {{audience}}")
    @test_suite = create_test_suite(cases: [
      { "topic" => "Ruby", "audience" => "beginners" },
      { "topic" => "Rust", "audience" => "experts" }
    ])
  end

  test "captures the adapter and prevents changes to its snapshot" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)
    assert_equal "ollama", trial.backend_adapter
    assert_not trial.update(backend_adapter: "unsupported")
    assert_includes trial.errors[:backend], "cannot be changed after the trial is created"
  end

  test "requires revisions, a backend, a model, and a valid status" do
    trial = Trial.new(model: "", status: "unknown")

    assert_not trial.valid?
    assert_includes trial.errors[:prompt_revision], "must exist"
    assert_includes trial.errors[:test_suite_revision], "must exist"
    assert_includes trial.errors[:backend], "must exist"
    assert_includes trial.errors[:model], "can't be blank"
    assert_includes trial.errors[:status], "is not included in the list"
  end

  test "defaults to pending" do
    assert_predicate create_trial(prompt: @prompt, test_suite: @test_suite), :pending?
  end

  test "refers to the current prompt and test suite revisions" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)

    assert_equal @prompt, trial.prompt_revision.prompt
    assert_equal @test_suite, trial.test_suite_revision.test_suite
    assert_equal [ 1, 1 ], [ trial.prompt_revision.version, trial.test_suite_revision.version ]
  end

  test "creates one rendered response per test case in position order" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)

    responses = trial.responses.joins(:test_suite_revision_case).order("test_suite_revision_cases.position")
    assert_equal [ "Explain Ruby to beginners", "Explain Rust to experts" ], responses.map(&:rendered_prompt)
    assert_equal trial.test_suite_revision.test_suite_revision_cases.to_a, responses.map(&:test_suite_revision_case)
    assert responses.all?(&:pending?)
  end

  test "keeps its rendered prompts after the prompt and test cases change" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)

    @prompt.update!(template: "Summarize {{topic}}")
    @test_suite.test_cases.first.update!(values: { "topic" => "Go", "audience" => "everyone" })
    later_trial = create_trial(prompt: @prompt, test_suite: @test_suite)

    assert_includes trial.reload.responses.map(&:rendered_prompt), "Explain Ruby to beginners"
    assert_equal [ 2, 2 ], [ later_trial.prompt_revision.version, later_trial.test_suite_revision.version ]
    assert_includes later_trial.responses.map(&:rendered_prompt), "Summarize Go"
  end

  test "requires the test suite to provide every variable used by the prompt" do
    prompt = create_prompt(template: "Explain {{topic}} in {{language}} for {{audience}}")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(prompt: prompt, test_suite: create_test_suite)
    end

    assert_includes error.record.errors[:test_suite], "does not provide variables used by the prompt: language and audience"
    assert_equal 0, Trial.count
    assert_equal 0, TestSuiteRevision.count
  end

  test "allows a test suite to provide variables the prompt does not use" do
    prompt = create_prompt(template: "Explain {{topic}}")

    trial = create_trial(prompt: prompt, test_suite: @test_suite)

    assert_equal [ "Explain Ruby", "Explain Rust" ], trial.responses.map(&:rendered_prompt).sort
  end

  test "cannot be created for a test suite without test cases" do
    test_suite = TestSuite.create!(name: "Empty", variables: [ "topic" ])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(prompt: create_prompt, test_suite: test_suite)
    end

    assert_includes error.record.errors[:test_suite], "must contain at least one test case"
  end

  test "cannot be created for an archived test suite" do
    @test_suite.archive!

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(prompt: @prompt, test_suite: @test_suite)
    end

    assert_includes error.record.errors[:test_suite], "has been archived"
  end

  test "cannot be created for a provisional test suite" do
    file = Rack::Test::UploadedFile.new(StringIO.new("topic\nRuby\n"), "text/csv", original_filename: "topics.csv")
    test_suite = TestSuite.import_csv!(file: file, header_row: true)

    error = assert_no_difference [ "Trial.count", "TestSuiteRevision.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) do
        create_trial(prompt: @prompt, test_suite: test_suite)
      end
    end

    assert_includes error.record.errors[:test_suite], "has not finished importing"
  end

  test "cannot be created for an archived prompt" do
    @prompt.archive!

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(prompt: @prompt, test_suite: @test_suite)
    end

    assert_includes error.record.errors[:prompt], "has been archived"
  end

  test "cannot be created for a disabled backend" do
    backend = Backend.create!(name: "Disabled", base_url: "http://disabled.local:8080", enabled: false)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(prompt: @prompt, test_suite: @test_suite, backend: backend)
    end

    assert_includes error.record.errors[:backend], "must be enabled"
  end

  test "destroys its responses" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)

    assert_difference "Response.count", -2 do
      trial.destroy!
    end
  end

  test "prevents its revisions from being deleted" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)

    assert_not trial.prompt_revision.destroy
    assert_not trial.test_suite_revision.destroy
    assert_not trial.responses.first.test_suite_revision_case.destroy
  end

  test "prevents its revisions from changing" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)
    @prompt.update!(template: "Summarize {{topic}}")

    assert_not trial.update(prompt_revision: PromptRevision.capture!(@prompt))
    assert_includes trial.errors[:base], "Prompt and test suite revisions cannot be changed after the trial is created"
  end

  test "Bedrock snapshots preserve the adapter and original endpoint without storing a region" do
    with_aws_region("us-east-1") do
      backend = Backend.create!(name: "AWS", adapter: "bedrock")
      trial = create_trial(prompt: @prompt, test_suite: @test_suite, backend: backend)
      snapshot = trial.backend_snapshot
      with_aws_region("us-west-2") do
        backend.update!(name: "New AWS")
        assert_equal snapshot, trial.reload.backend_snapshot
        assert_equal "bedrock", trial.backend_adapter
        assert_equal "https://bedrock-runtime.us-east-1.amazonaws.com", trial.backend_base_url
        assert_equal "https://bedrock-runtime.us-west-2.amazonaws.com", create_trial(prompt: @prompt, test_suite: @test_suite, backend: backend).backend_base_url
      end
      assert_not trial.update(backend_adapter: "ollama")
    end
  end

  test "snapshots its backend execution input and prevents it from changing" do
    backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")
    trial = create_trial(prompt: @prompt, test_suite: @test_suite, backend: backend)

    backend.update!(name: "Renamed Ollama")

    assert_equal "Local Ollama", trial.reload.backend_name
    assert_equal "http://ollama:11434", trial.backend_base_url

    replacement = Backend.create!(name: "Edge board", base_url: "http://edge.local:8080")
    assert_not trial.update(backend: replacement)
    assert_includes trial.errors[:backend], "cannot be changed after the trial is created"
  end

  test "prevents its backend from being deleted" do
    backend = Backend.create!(name: "Edge board", base_url: "http://edge.local:8080")
    create_trial(prompt: @prompt, test_suite: @test_suite, backend: backend)

    assert_not backend.destroy
    assert_includes backend.errors[:base], "Cannot delete record because dependent trials exist"
  end
end
