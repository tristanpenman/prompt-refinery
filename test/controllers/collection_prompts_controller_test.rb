require "test_helper"

class CollectionPromptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @collection = Collection.create!(name: "Examples")
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "creates and updates a prompt" do
    assert_difference "Prompt.count", 1 do
      post collection_prompts_path(@collection), params: {
        prompt: { name: "Explain", template: "Explain {{topic}}", position: 0 }
      }
    end

    prompt = Prompt.last
    assert_redirected_to @collection

    patch collection_prompt_path(@collection, prompt), params: {
      prompt: { name: "Summarize", template: "Summarize {{topic}}", position: 1 }
    }

    assert_redirected_to @collection
    assert_equal [ "Summarize", "Summarize {{topic}}", 1 ], prompt.reload.attributes.values_at("name", "template", "position")
  end

  test "soft deletes a prompt" do
    prompt = @collection.prompts.create!(name: "Example", template: "Hello")

    assert_no_difference "Prompt.count" do
      delete collection_prompt_path(@collection, prompt)
    end

    assert_redirected_to @collection
    assert_not_nil prompt.reload.deleted_at
    assert_not_includes @collection.prompts.reload, prompt
  end

  test "soft deletes a prompt that has been used in a trial" do
    prompt = @collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(prompt: prompt)

    assert_no_difference [ "Prompt.count", "Response.count" ] do
      delete collection_prompt_path(@collection, prompt)
    end

    assert_redirected_to @collection
    assert_not_nil prompt.reload.deleted_at
    assert_equal prompt, trial.prompt_revision.prompt
  end

  test "does not access a prompt through another collection" do
    prompt = @collection.prompts.create!(name: "Example", template: "Hello")
    other_collection = Collection.create!(name: "Other")

    patch collection_prompt_path(other_collection, prompt), params: {
      prompt: { name: "Changed", template: "Changed", position: 0 }
    }

    assert_response :not_found
    assert_equal "Example", prompt.reload.name
  end

  test "does not change prompts in an archived collection" do
    prompt = @collection.prompts.create!(name: "Example", template: "Hello", position: 0)
    @collection.archive!

    assert_no_difference "Prompt.count" do
      post collection_prompts_path(@collection), params: {
        prompt: { name: "New", template: "New", position: 1 }
      }
    end
    assert_redirected_to @collection

    patch collection_prompt_path(@collection, prompt), params: {
      prompt: { name: "Changed", template: "Changed", position: 1 }
    }
    assert_redirected_to @collection
    assert_equal [ "Example", "Hello", 0 ], prompt.reload.attributes.values_at("name", "template", "position")

    delete collection_prompt_path(@collection, prompt)
    assert_redirected_to @collection
    assert_nil prompt.reload.deleted_at
  end
end
