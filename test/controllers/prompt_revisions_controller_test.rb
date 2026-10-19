require "test_helper"

class PromptRevisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows prompt revisions newest first with their trial counts" do
    prompt = create_prompt(template: "Original {{topic}}")
    create_trial(prompt: prompt)
    prompt.update!(template: "Updated {{topic}}")
    create_trial(prompt: prompt)

    get revisions_prompt_path(prompt)

    assert_response :success
    assert_select ".editor-card", count: 2
    assert_select ".current-revision", text: /Revision 2 · .* · 1 trial/m
    assert_select ".current-revision", text: /Updated \{\{topic\}\}/
    assert_select ".revision-list .editor-card", text: /Revision 1/
    assert_select ".revision-list .editor-card", text: /Original \{\{topic\}\}/
  end

  test "shows an empty state before the prompt is used" do
    prompt = create_prompt

    get revisions_prompt_path(prompt)

    assert_response :success
    assert_select ".current-revision", text: /Draft · will become r1/i
    assert_select ".notice", text: /No previous revisions yet/
  end
end
