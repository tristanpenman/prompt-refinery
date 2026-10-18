require "test_helper"

class LanguageModelTest < ActiveSupport::TestCase
  setup do
    @backend = Backend.ensure_system_default!
    @family = LanguageModelFamily.create!(name: "Gemma 3")
  end

  test "requires a backend, family, and name" do
    model = LanguageModel.new(name: "")

    assert_not model.valid?
    assert_includes model.errors[:backend], "must exist"
    assert_includes model.errors[:language_model_family], "must exist"
    assert_includes model.errors[:name], "can't be blank"
  end

  test "derives the family name from the model name up to the first colon" do
    assert_equal "gemma3", LanguageModel.family_name_for("gemma3:4b")
    assert_equal "qwen2.5-coder", LanguageModel.family_name_for("qwen2.5-coder:7b")
    assert_equal "llama3", LanguageModel.family_name_for("llama3")
    assert_nil LanguageModel.family_name_for(":latest")
    assert_nil LanguageModel.family_name_for("")
  end

  test "assigns a derived family when none is given" do
    model = LanguageModel.create!(backend: @backend, name: "qwen2.5-coder:7b")

    assert_equal "qwen2.5-coder", model.language_model_family.name
  end

  test "reuses an existing family with the derived name" do
    family = LanguageModelFamily.create!(name: "gemma3")
    edge_backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")

    first = LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    second = LanguageModel.create!(backend: edge_backend, name: "gemma3:12b")

    assert_equal family, first.language_model_family
    assert_equal family, second.language_model_family
    assert_equal 1, LanguageModelFamily.where(name: "gemma3").count
  end

  test "keeps an explicitly assigned family" do
    model = LanguageModel.create!(backend: @backend, language_model_family: @family, name: "gemma3:4b")

    assert_equal @family, model.language_model_family
    assert_not LanguageModelFamily.exists?(name: "gemma3")
  end

  test "requires a family when one cannot be derived from the name" do
    model = LanguageModel.new(backend: @backend, name: ":latest")

    assert_not model.valid?
    assert_includes model.errors[:language_model_family], "must exist"
  end

  test "name must be unique per backend" do
    LanguageModel.create!(backend: @backend, language_model_family: @family, name: "gemma3:4b")

    duplicate = LanguageModel.new(backend: @backend, language_model_family: @family, name: "gemma3:4b")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"

    other_backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")
    assert LanguageModel.new(backend: other_backend, language_model_family: @family, name: "gemma3:4b").valid?
  end

  test "is destroyed along with its backend" do
    backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")
    model = LanguageModel.create!(backend: backend, language_model_family: @family, name: "gemma3:4b")

    backend.destroy!

    assert_not LanguageModel.exists?(model.id)
    assert LanguageModelFamily.exists?(@family.id)
  end
end
