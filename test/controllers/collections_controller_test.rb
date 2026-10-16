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
    collection = Collection.create!(name: "Summaries")
    collection.prompts.create!(name: "Example", template: "Original")
    create_trial(collection: collection)

    get collections_path

    assert_response :success
    assert_select "th", text: "Revision"
    assert_select "th", text: "Draft"
    assert_select "th", text: "Created"
    assert_select "th", text: "Updated"
    assert_select "tr", text: /Summaries\s+r1\s+Recorded\s+1/
  end

  test "shows the latest recorded revision for a draft collection" do
    collection = Collection.create!(name: "Draft summaries")
    prompt = collection.prompts.create!(name: "Example", template: "Original")
    create_trial(collection: collection)
    prompt.update!(template: "Draft edit")

    get collections_path

    assert_response :success
    assert_select "tr", text: /Draft summaries\s+r1\s+Draft\s+1/
  end

  test "shows N/A when a collection has no recorded revision" do
    collection = Collection.create!(name: "Unrecorded")
    collection.prompts.create!(name: "Example", template: "Original")

    get collections_path

    assert_response :success
    assert_select "tr", text: /Unrecorded\s+N\/A\s+Draft\s+1/
  end

  test "switches between active and archived collections" do
    active = Collection.create!(name: "Active collection")
    archived = Collection.create!(name: "Archived collection")
    archived.archive!

    get collections_path

    assert_response :success
    assert_select "a", text: active.name
    assert_select "a", text: archived.name, count: 0
    assert_select "a[href=?]", collections_path(archived: true), text: "View archived collections"

    get collections_path(archived: true)

    assert_response :success
    assert_select "h2", text: "Archived collections"
    assert_select "a", text: archived.name
    assert_select "a", text: active.name, count: 0
    assert_select "a[href=?]", collections_path, text: "View active collections"
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

  test "archives a collection without deleting it or its prompts" do
    collection = Collection.create!(name: "Disposable")
    prompt = collection.prompts.create!(name: "Example", template: "Hello")

    assert_no_difference [ "Collection.count", "Prompt.count" ] do
      delete collection_path(collection)
    end

    assert_redirected_to collections_path
    assert_not_nil collection.reload.archived_at
    assert Prompt.exists?(prompt.id)

    get collections_path
    assert_select "a", text: "Disposable", count: 0
  end

  test "archives a collection that has been used by a trial" do
    collection = Collection.create!(name: "Retained")
    collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(collection: collection)

    assert_no_difference [ "Collection.count", "Trial.count" ] do
      delete collection_path(collection)
    end

    assert_redirected_to collections_path
    assert_not_nil collection.reload.archived_at

    get trial_path(trial)
    assert_response :success
    assert_select "h1", text: "Retained"
  end

  test "shows archived status and unarchives a collection" do
    collection = Collection.create!(name: "Restorable")
    collection.prompts.create!(name: "Original prompt", template: "Read-only content", position: 0)
    collection.archive!

    get collection_path(collection)

    assert_response :success
    assert_select ".collection-heading h1", text: "Restorable"
    assert_select ".collection-heading .status--archived", text: "Archived"
    assert_select "a[href=?][data-turbo-method=patch]", unarchive_collection_path(collection), text: "Unarchive collection"
    assert_select "input[name='collection[name]']", count: 0
    assert_select "textarea", count: 0
    assert_select "button", text: "Archive collection", count: 0
    assert_select "button", text: "Delete prompt", count: 0
    assert_select "h2", text: "Add prompt", count: 0
    assert_select ".archived-prompt-card h3", text: "Original prompt"
    assert_select ".prompt-list", text: /Original prompt.*Read-only content/m

    patch collection_path(collection), params: { collection: { name: "Changed" } }

    assert_redirected_to collection
    assert_equal "Restorable", collection.reload.name

    patch unarchive_collection_path(collection)

    assert_redirected_to collection
    assert_nil collection.reload.archived_at
  end
end
