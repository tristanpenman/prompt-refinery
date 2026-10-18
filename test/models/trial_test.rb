require "test_helper"

class TrialTest < ActiveSupport::TestCase
  setup do
    @collection = Collection.create!(name: "Examples")
  end

  test "requires a collection, backend, model, and valid status" do
    trial = Trial.new(model: "", status: "unknown")

    assert_not trial.valid?
    assert_includes trial.errors[:collection], "must exist"
    assert_includes trial.errors[:backend], "must exist"
    assert_includes trial.errors[:model], "can't be blank"
    assert_includes trial.errors[:status], "is not included in the list"
  end

  test "defaults to pending" do
    @collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(collection: @collection)

    assert_predicate trial, :pending?
  end

  test "cannot be created for an archived collection" do
    @collection.archive!

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(collection: @collection)
    end

    assert_includes error.record.errors[:collection], "has been archived"
  end

  test "cannot be created for a collection without prompts" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(collection: @collection)
    end

    assert_includes error.record.errors[:collection], "must contain at least one prompt"
  end

  test "cannot be created for a disabled backend" do
    @collection.prompts.create!(name: "Example", template: "Hello")
    backend = Backend.create!(name: "Disabled", base_url: "http://disabled.local:8080", enabled: false)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(collection: @collection, backend: backend)
    end

    assert_includes error.record.errors[:backend], "must be enabled"
  end

  test "destroys its responses" do
    prompt = @collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(collection: @collection)
    response = trial.responses.find_by!(prompt: prompt)

    trial.destroy!

    assert_not Response.exists?(response.id)
  end

  test "prevents its collection from being deleted" do
    @collection.prompts.create!(name: "Example", template: "Hello")
    create_trial(collection: @collection)

    assert_not @collection.destroy
    assert_includes @collection.errors[:base], "Cannot delete record because dependent trials exist"
  end

  test "snapshots its backend execution input and prevents it from changing" do
    @collection.prompts.create!(name: "Example", template: "Hello")
    backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")
    trial = create_trial(collection: @collection, backend: backend)

    backend.update!(name: "Renamed Ollama")

    assert_equal "Local Ollama", trial.reload.backend_name
    assert_equal "http://ollama:11434", trial.backend_base_url

    replacement = Backend.create!(name: "Edge board", base_url: "http://edge.local:8080")
    assert_not trial.update(backend: replacement)
    assert_includes trial.errors[:backend], "cannot be changed after the trial is created"
  end

  test "prevents its backend from being deleted" do
    @collection.prompts.create!(name: "Example", template: "Hello")
    backend = Backend.create!(name: "Edge board", base_url: "http://edge.local:8080")
    create_trial(collection: @collection, backend: backend)

    assert_not backend.destroy
    assert_includes backend.errors[:base], "Cannot delete record because dependent trials exist"
  end
end
