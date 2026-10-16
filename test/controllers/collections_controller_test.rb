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

  test "shows the current revision and draft state" do
    collection = Collection.create!(name: "Revised")
    prompt = collection.prompts.create!(name: "Example", template: "Original")
    create_trial(collection: collection)
    prompt.update!(template: "Draft edit")

    get collection_path(collection)

    assert_response :success
    assert_select "p", text: /Latest revision:\s+r1/
    assert_select "p", text: /There are draft changes/
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

  test "explains why a collection used by a trial cannot be deleted" do
    collection = Collection.create!(name: "Retained")
    trial = create_trial(collection: collection)

    assert_no_difference [ "Collection.count", "Trial.count" ] do
      delete collection_path(collection)
    end

    assert_redirected_to collection
    follow_redirect!
    assert_response :success
    assert_select "[role=alert]", text: "A collection cannot be deleted after it has been used to create a trial."
    assert Collection.exists?(collection.id)
    assert Trial.exists?(trial.id)
  end
end
