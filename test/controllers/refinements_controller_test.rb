require "test_helper"

class RefinementsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @backend = Backend.ensure_system_default!
    @student = LanguageModel.create!(backend: @backend, name: "llama3.2:3b")
    @teacher = LanguageModel.create!(backend: @backend, name: "qwen2.5:7b")
    @prompt = create_prompt(template: "Explain {{topic}}")
    @test_suite = create_test_suite
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows a form for a new refinement with the defaults" do
    get refinements_path

    assert_response :success
    assert_select "h1", text: "Refinements"
    assert_select "form[action=?][method=post]", refinements_path do
      assert_select "select[name='refinement[prompt_id]'] option", text: "Explain"
      assert_select "select[name='refinement[test_suite_id]'] option", text: "Topics"
      assert_select "select[name='refinement[student_language_model_id]'] optgroup[label='Local Ollama']" do
        assert_select "option[value=?]", @student.id.to_s, text: "llama3.2:3b"
        assert_select "option[value=?]", @teacher.id.to_s, text: "qwen2.5:7b"
      end
      assert_select "select[name='refinement[teacher_language_model_id]'] option[value=?]", @teacher.id.to_s
      assert_select "input[name='refinement[max_iterations]'][value='3']"
      assert_select "input[name='refinement[target_agreement]'][value='1.0']"
      assert_select "input[name='refinement[context_size]'][value='16384']"
      assert_select "textarea[name='refinement[instructions]']", text: /\{\{current_prompt\}\}/
    end
    assert_select ".resource-list p", text: "No refinements yet."
  end

  test "only offers models on enabled backends and prompts that aren't working copies" do
    disabled = Backend.create!(name: "Old server", base_url: "http://old.test:11434", enabled: false)
    LanguageModel.create!(backend: disabled, name: "mistral:7b")
    create_refinement

    get refinements_path

    assert_select "option", text: "mistral:7b", count: 0
    assert_select "optgroup[label='Old server']", count: 0
    assert_select "select[name='refinement[prompt_id]'] option", text: /\(refinement 1\)/, count: 0
  end

  test "explains what's missing before a refinement can be created" do
    LanguageModel.delete_all

    get refinements_path

    assert_select "form[action=?]", refinements_path, count: 0
    assert_select "a[href=?]", settings_models_path, text: "Refresh models"
  end

  test "creates a refinement with a working copy of the prompt" do
    assert_difference -> { PromptRefinement.count } => 1, -> { Prompt.count } => 1 do
      post refinements_path, params: { refinement: refinement_params(max_iterations: "5", target_agreement: "0.9") }
    end

    refinement = PromptRefinement.last
    assert_redirected_to refinement_path(refinement)
    assert_equal "Refinement created.", flash[:notice]
    assert_predicate refinement, :pending?
    assert_equal "Explain", refinement.name
    assert_equal @prompt, refinement.starting_prompt_revision.prompt
    assert_equal "Explain (refinement 1)", refinement.prompt.name
    assert_equal "Explain {{topic}}", refinement.prompt.template
    assert_equal @test_suite, refinement.test_suite_revision.test_suite
    assert_equal [ @backend, "llama3.2:3b" ], [ refinement.student_backend, refinement.student_model ]
    assert_equal [ @backend, "qwen2.5:7b" ], [ refinement.teacher_backend, refinement.teacher_model ]
    assert_equal 5, refinement.max_iterations
    assert_equal 0.9, refinement.target_agreement
  end

  test "lists existing refinements with a link to manage them" do
    refinement = create_refinement

    get refinements_path

    assert_select ".resource-list th", text: "Iterations", count: 0
    assert_select ".resource-list th", text: "Best agreement", count: 0
    assert_select ".resource-list tbody tr", count: 1
    assert_select ".resource-list tbody tr",
      text: /Explain r1\s+Topics r1\s+llama3.2:3b \(Local Ollama\)\s+qwen2.5:7b \(Local Ollama\)\s+Pending\s+less than a minute ago\s+Manage/
    assert_select ".resource-list tbody tr a[href=?]", refinement_path(refinement), text: "Manage"
  end

  test "shows a refinement's details" do
    refinement = create_refinement

    get refinement_path(refinement)

    assert_response :success
    assert_select "h1", text: /Explain\s+Pending/
    assert_select ".refinement-details" do
      assert_select "a[href=?]", prompt_path(@prompt), text: "Explain"
      assert_select "a[href=?]", prompt_path(refinement.prompt), text: "Explain (refinement 1)"
      assert_select "a[href=?]", test_suite_path(@test_suite), text: "Topics"
      assert_select "dd", text: "llama3.2:3b (Local Ollama)"
      assert_select "dd", text: "qwen2.5:7b (Local Ollama)"
      assert_select "dd", text: "Not run yet"
      assert_select "dd", text: "0 of 3"
      assert_select "dd", text: "100%"
      assert_select "dd", text: "16,384 tokens"
      assert_select "details summary", text: "Teacher instructions"
    end
    assert_select ".refinement-iterations p", text: "No iterations yet."
    assert_select "form[action=?][method=post] button", run_refinement_path(refinement), text: "Run iteration"
    assert_select "meta[http-equiv=refresh]", count: 0
  end

  test "queues an iteration and marks the refinement as running" do
    refinement = create_refinement

    assert_enqueued_with(job: RefinementJob, args: [ refinement ]) do
      post run_refinement_path(refinement)
    end

    assert_redirected_to refinement_path(refinement)
    assert_equal "Iteration queued.", flash[:notice]
    assert_predicate refinement.reload, :running?
    assert_not_nil refinement.started_at

    follow_redirect!
    assert_select ".notice h2", text: "Running an iteration…"
    assert_select "meta[http-equiv=refresh][content='2']"
    assert_select "button", text: "Run iteration", count: 0
  end

  test "doesn't queue an iteration while one is running" do
    refinement = create_refinement
    refinement.update!(status: :running)

    assert_no_enqueued_jobs do
      post run_refinement_path(refinement)
    end

    assert_redirected_to refinement_path(refinement)
    assert_equal "This refinement can't run another iteration.", flash[:alert]
  end

  test "doesn't offer another iteration once the limit is reached" do
    refinement = create_refinement
    refinement.update!(max_iterations: 1)
    revision = PromptRevision.capture!(refinement.prompt)
    refinement.iterations.create!(number: 1, prompt_revision: revision, status: "completed")

    get refinement_path(refinement)
    assert_select "button", text: "Run iteration", count: 0
    assert_select "dd", text: "1 of 1"

    assert_no_enqueued_jobs do
      post run_refinement_path(refinement)
    end
    assert_equal "This refinement can't run another iteration.", flash[:alert]
  end

  test "shows the results of each iteration" do
    refinement = create_refinement
    test_cases = refinement.test_suite_revision.test_suite_revision_cases.to_a
    revision = PromptRevision.capture!(refinement.prompt)
    refinement.iterations.create!(
      number: 1,
      prompt_revision: revision,
      status: "completed",
      agreement: 0.5,
      summary: "Too verbose.",
      change_summary: "Asked for one sentence.",
      proposed_template: "Explain {{topic}} in one sentence",
      case_evaluations: test_cases.each_with_index.to_h { |test_case, index|
        [ test_case.id.to_s, { "verdict" => index.zero? ? "match" : "miss", "notes" => "Note #{index + 1}" } ]
      }
    )
    refinement.iterations.create!(number: 2, prompt_revision: revision, status: "failed", error: "Teacher reply was not JSON")

    get refinement_path(refinement)

    assert_select ".refinement-iterations article", count: 2
    assert_select ".refinement-iterations article:nth-of-type(1)" do
      assert_select "h3", text: "Iteration 1"
      assert_select ".status--completed", text: "Completed"
      assert_select "p", text: /Agreement: 50%/
      assert_select "p", text: /Prompt: r#{revision.version}/
      assert_select ".result-content", text: "Too verbose."
      assert_select ".result-content", text: "Asked for one sentence."
      assert_select ".case-evaluations li", count: test_cases.size
      assert_select ".case-evaluations li:first-child", text: /Test case 1\s+Match\s+Note 1/
      assert_select "details summary", text: "Proposed prompt"
    end
    assert_select ".refinement-iterations article:nth-of-type(2)" do
      assert_select "h3", text: "Iteration 2"
      assert_select "p", text: /Agreement: N\/A/
      assert_select ".form-error", text: "Teacher reply was not JSON"
    end
  end

  test "shows a missing refinement as not found" do
    get refinement_path(id: 0)

    assert_response :not_found
  end

  test "shows errors when the refinement can't be created" do
    assert_no_difference -> { PromptRefinement.count } do
      post refinements_path, params: {
        refinement: refinement_params(teacher_language_model_id: "", instructions: "Improve {{current_prompt}} for {{tone}}")
      }
    end

    assert_response :unprocessable_content
    assert_select ".form-error li", text: "Teacher model must be a model on an enabled backend"
    assert_select "select[name='refinement[student_language_model_id]'] option[selected][value=?]", @student.id.to_s
    assert_select "textarea[name='refinement[instructions]']", text: "Improve {{current_prompt}} for {{tone}}"
  end

  test "keeps nothing when the refinement fails validation" do
    assert_no_difference [ "PromptRefinement.count", "Prompt.count", "PromptRevision.count", "TestSuiteRevision.count" ] do
      post refinements_path, params: { refinement: refinement_params(instructions: "Improve {{current_prompt}} for {{tone}}") }
    end

    assert_response :unprocessable_content
    assert_select ".form-error li", text: /Instructions use unknown variable tone/
  end

  test "requires authentication" do
    delete logout_path

    get refinements_path

    assert_redirected_to login_path(return_to: refinements_path)
  end

  private

  def refinement_params(**overrides)
    {
      prompt_id: @prompt.id,
      test_suite_id: @test_suite.id,
      student_language_model_id: @student.id,
      teacher_language_model_id: @teacher.id,
      max_iterations: "3",
      target_agreement: "1",
      context_size: "16384",
      instructions: PromptRefinement.default_instructions
    }.merge(overrides)
  end

  def create_refinement
    PromptRefinement.create_for!(prompt: @prompt, test_suite: @test_suite, student: @student, teacher: @teacher)
  end
end
