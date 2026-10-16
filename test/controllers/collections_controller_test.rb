require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists collections" do
    Collection.create!(name: "Summaries")

    get collections_path

    assert_response :success
    assert_select "h3", text: "Summaries"
  end

  test "creates and updates a collection" do
    assert_difference "Collection.count", 1 do
      post collections_path, params: { collection: { name: "Drafts" } }
    end

    collection = Collection.last
    assert_redirected_to collection

    patch collection_path(collection), params: { collection: { name: "Published" } }

    assert_redirected_to collection
    assert_equal "Published", collection.reload.name
  end

  test "deletes a collection and its prompts" do
    collection = Collection.create!(name: "Disposable")
    collection.prompts.create!(name: "Example", template: "Hello")

    assert_difference [ "Collection.count", "Prompt.count" ], -1 do
      delete collection_path(collection)
    end

    assert_redirected_to collections_path
  end
end
