require "test_helper"

class TrialsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")
    @prompt = create_prompt(template: "Explain {{topic}}")
    @test_suite = create_test_suite(cases: [ { "topic" => "Ruby" }, { "topic" => "Rust" } ])
    TrialsController.client_factory = available_models_factory
  end

  teardown do
    TrialsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists trials and creation options" do
    trial = create_trial(prompt: @prompt, test_suite: @test_suite)

    get trials_path

    assert_response :success
    assert_select "select[name='trial[prompt_id]'] optgroup[label=?] option", "Examples", text: "Explain"
    assert_select "select[name='trial[test_suite_id]'] option", text: "Topics"
    assert_select "select[name=backend_id] option", text: @backend.name
    assert_select "option", text: "gemma3:4b"
    assert_select "section.editor-card.trial-list" do
      assert_select "h2", text: "Previous trials"
      assert_select "table"
    end
    assert_select "a[href=?]", trial_path(trial), text: "Explain r1"
    assert_select "tr", text: /Explain r1\s+Topics r1\s+#{Regexp.escape(@backend.name)}\s+gemma3:4b/
  end

  test "creates one response per test case and enqueues the trial" do
    assert_enqueued_with(job: TrialExecutionJob) do
      assert_difference "Trial.count", 1 do
        assert_difference "Response.count", 2 do
          post trials_path, params: { trial: trial_params }
        end
      end
    end

    trial = Trial.last
    assert_redirected_to trial
    assert_equal @backend, trial.backend
    assert_equal @backend.name, trial.backend_name
    assert_equal @backend.base_url, trial.backend_base_url
    assert_equal @prompt, trial.prompt_revision.prompt
    assert_equal @test_suite, trial.test_suite_revision.test_suite
    assert_equal [ "Explain Ruby", "Explain Rust" ], trial.responses.map(&:rendered_prompt).sort
  end

  test "rejects a test suite that does not provide the prompt's variables" do
    prompt = create_prompt(template: "Explain {{topic}} to {{audience}}")

    assert_no_enqueued_jobs do
      assert_no_difference [ "Trial.count", "PromptRevision.count", "TestSuiteRevision.count" ] do
        post trials_path, params: { trial: trial_params(prompt_id: prompt.id) }
      end
    end

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Test suite does not provide variable used by the prompt: audience/
    assert_select "select[name='trial[prompt_id]'] option[selected][value=?]", prompt.id.to_s
    assert_select "select[name='trial[test_suite_id]'] option[selected][value=?]", @test_suite.id.to_s
  end

  test "does not offer or create a trial for an archived test suite" do
    existing_trial = create_trial(prompt: @prompt, test_suite: @test_suite)
    @test_suite.archive!

    get trials_path

    assert_response :success
    assert_select "select[name='trial[test_suite_id]'] option", text: "Topics", count: 0
    assert_select "a[href=?]", trial_path(existing_trial)

    assert_no_difference "Trial.count" do
      post trials_path, params: { trial: trial_params }
    end

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Test suite must exist/
  end

  test "does not offer a test suite without test cases" do
    TestSuite.create!(name: "Empty", variables: [ "topic" ])

    get trials_path

    assert_response :success
    assert_select "select[name='trial[test_suite_id]'] option", text: "Empty", count: 0
  end

  test "does not offer or create a trial for a prompt in an archived collection" do
    @prompt.collection.archive!

    get trials_path

    assert_response :success
    assert_select "option", text: "Explain", count: 0

    assert_no_difference "Trial.count" do
      post trials_path, params: { trial: trial_params }
    end

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Prompt must exist/
  end

  test "shows a response for each test case" do
    created_at = Time.zone.local(2026, 10, 16, 14, 30)
    trial = create_trial(prompt: @prompt, test_suite: @test_suite, status: :completed, created_at: created_at)
    trial.responses.find_by!(rendered_prompt: "Explain Ruby").update!(status: :completed, content: "**Generated** response")

    get trial_path(trial)

    assert_response :success
    assert_select ".trials-page > header h1", text: "Explain"
    assert_select "section.editor-card" do
      assert_select "h2", text: "Trial details"
      assert_select ".status.status--completed", text: "Completed"
      assert_select "p", text: "Prompt: Explain r1"
      assert_select "p", text: "Test suite: Topics r1"
      assert_select "a[href=?]", test_suite_path(@test_suite), text: "Topics"
      assert_select "time[datetime=?]", created_at.iso8601, text: created_at.to_fs(:long)
      assert_select "a[href=?]", compare_trial_path(trial), text: "Compare trial"
    end
    assert_select ".trial-responses article", count: 2
    assert_select ".trial-responses article:nth-of-type(1)" do
      assert_select "h3", text: /Test case 1\s+r1/
      assert_select "dd", text: "Ruby"
      assert_select ".response-prompt", text: /Prompt\s+Explain Ruby/
      assert_select ".result-content.markdown-content strong", text: "Generated"
    end
    assert_select ".trial-responses article:nth-of-type(2) .response-prompt", text: /Prompt\s+Explain Rust/
  end

  private

  def trial_params(**overrides)
    { prompt_id: @prompt.id, test_suite_id: @test_suite.id, backend_id: @backend.id, model: "gemma3:4b" }.merge(overrides)
  end

  def available_models_factory
    client = Class.new do
      def models
        [ { "name" => "gemma3:4b" } ]
      end
    end
    Class.new do
      define_singleton_method(:for) { |_backend, **_options| client.new }
    end
  end
end
