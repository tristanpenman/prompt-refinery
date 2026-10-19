require "test_helper"

class PromptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists prompts with their variables and revision state" do
    recorded = create_prompt(name: "Recorded", template: "Explain {{topic}} to {{audience}}")
    PromptRevision.capture!(recorded)
    create_prompt(name: "Unrecorded", template: "Hello")

    get prompts_path

    assert_response :success
    assert_select "th", text: "Revision"
    assert_select "th", text: "Variables"
    assert_select "tr", text: /Recorded\s+r1\s+Recorded\s+topic, audience/
    assert_select "tr", text: /Unrecorded\s+N\/A\s+Draft\s+None/
  end

  test "switches between active and archived prompts" do
    active = create_prompt(name: "Active prompt")
    archived = create_prompt(name: "Archived prompt")
    archived.archive!

    get prompts_path

    assert_response :success
    assert_select "a", text: active.name
    assert_select "a", text: archived.name, count: 0

    get prompts_path(archived: true)

    assert_response :success
    assert_select "h2", text: "Archived prompts"
    assert_select "a", text: archived.name
    assert_select "a", text: active.name, count: 0
  end

  test "creates and updates a prompt" do
    assert_difference "Prompt.count", 1 do
      post prompts_path, params: { prompt: { name: "Explain", template: "Explain {{topic}}" } }
    end

    prompt = Prompt.last
    assert_redirected_to prompt

    patch prompt_path(prompt), params: { prompt: { name: "Summarize", template: "Summarize {{topic}}" } }

    assert_redirected_to prompt
    assert_equal [ "Summarize", "Summarize {{topic}}" ], prompt.reload.attributes.values_at("name", "template")
  end

  test "rerenders the form when a prompt is invalid" do
    prompt = create_prompt(name: "Explain")

    patch prompt_path(prompt), params: { prompt: { name: "", template: "Changed" } }

    assert_response :unprocessable_content
    assert_select ".form-error", text: /Name can't be blank/
    assert_select "h1", text: "Explain"
  end

  test "shows the latest revision and draft state" do
    prompt = create_prompt
    PromptRevision.capture!(prompt)
    prompt.update!(template: "Draft edit")

    get prompt_path(prompt)

    assert_response :success
    assert_select "p", text: /Latest revision:\s+r1/
    assert_select "a[href=?]", revisions_prompt_path(prompt), text: "View revision history"
    assert_select "p", text: /There are draft changes/
  end

  test "archives a prompt that has been used by a trial and unarchives it" do
    prompt = create_prompt
    trial = create_trial(prompt: prompt)

    assert_no_difference [ "Prompt.count", "Trial.count" ] do
      delete prompt_path(prompt)
    end

    assert_redirected_to prompts_path
    assert_not_nil prompt.reload.archived_at

    get prompt_path(prompt)
    assert_select "h1 .status--archived", text: "Archived"
    assert_select "textarea", count: 0
    assert_select "a[href=?][data-turbo-method=patch]", unarchive_prompt_path(prompt), text: "Unarchive prompt"

    patch prompt_path(prompt), params: { prompt: { name: "Changed" } }
    assert_redirected_to prompt
    assert_equal "Explain", prompt.reload.name

    get trial_path(trial)
    assert_response :success

    patch unarchive_prompt_path(prompt)
    assert_redirected_to prompt
    assert_nil prompt.reload.archived_at
  end
end
