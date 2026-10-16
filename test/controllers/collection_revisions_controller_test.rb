require "test_helper"

class CollectionRevisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows collection revisions newest first with their prompt snapshots" do
    collection = Collection.create!(name: "Examples")
    prompt = collection.prompts.create!(name: "Greeting", template: "Original prompt")
    create_trial(collection: collection)
    prompt.update!(template: "Updated prompt")
    create_trial(collection: collection)

    get revisions_collection_path(collection)

    assert_response :success
    assert_select ".editor-card", count: 2
    assert_select ".current-revision", text: /r2/
    assert_select ".current-revision", text: /Updated prompt/
    assert_select ".revision-list .editor-card", text: /Revision 1/
    assert_select ".revision-list .editor-card", text: /Original prompt/
  end

  test "shows an empty state before the collection is used" do
    collection = Collection.create!(name: "Draft")

    get revisions_collection_path(collection)

    assert_response :success
    assert_select ".current-revision", text: /Draft · will become r1/i
    assert_select ".notice", text: /No previous revisions yet/
  end
end
