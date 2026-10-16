require "test_helper"

class CollectionVersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows collection versions newest first with their prompt snapshots" do
    collection = Collection.create!(name: "Examples")
    prompt = collection.prompts.create!(name: "Greeting", template: "Original prompt")
    create_trial(collection: collection)
    prompt.update!(template: "Updated prompt")
    create_trial(collection: collection)

    get versions_collection_path(collection)

    assert_response :success
    assert_select ".editor-card", count: 2
    assert_select ".current-version h2", text: "Current version"
    assert_select ".current-version", text: /Updated prompt/
    assert_select ".current-version", text: /v2/
    assert_select ".version-list .editor-card h2", text: "Version 1"
    assert_select ".version-list .editor-card", text: /Original prompt/
  end

  test "shows an empty state before the collection is used" do
    collection = Collection.create!(name: "Draft")

    get versions_collection_path(collection)

    assert_response :success
    assert_select ".current-version", text: /Draft · will become v1/
    assert_select ".notice", text: /No previous versions yet/
  end
end
