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

  test "deletes the previous family when its last model moves to another family" do
    model = LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    previous_family = model.language_model_family

    model.update!(language_model_family: @family)

    assert_not LanguageModelFamily.exists?(previous_family.id)
    assert LanguageModelFamily.exists?(@family.id)
  end

  test "keeps the previous family while it still has models" do
    model = LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    LanguageModel.create!(backend: @backend, name: "gemma3:12b")
    previous_family = model.language_model_family

    model.update!(language_model_family: @family)

    assert LanguageModelFamily.exists?(previous_family.id)
    assert_equal [ "gemma3:12b" ], previous_family.language_models.pluck(:name)
  end

  test "keeps the family when other attributes change" do
    model = LanguageModel.create!(backend: @backend, language_model_family: @family, name: "gemma3:4b")

    model.update!(name: "gemma3:4b-it")

    assert LanguageModelFamily.exists?(@family.id)
  end

  test "name must be unique per backend" do
    LanguageModel.create!(backend: @backend, language_model_family: @family, name: "gemma3:4b")

    duplicate = LanguageModel.new(backend: @backend, language_model_family: @family, name: "gemma3:4b")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"

    other_backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")
    assert LanguageModel.new(backend: other_backend, language_model_family: @family, name: "gemma3:4b").valid?
  end

  test "deletes its family when the last model in it is destroyed" do
    model = LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    other = LanguageModel.create!(backend: @backend, name: "gemma3:12b")
    family = model.language_model_family

    model.destroy!
    assert LanguageModelFamily.exists?(family.id)

    other.destroy!
    assert_not LanguageModelFamily.exists?(family.id)
  end

  test "is destroyed along with its backend, removing families left empty" do
    edge_backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")
    model = LanguageModel.create!(backend: edge_backend, name: "gemma3:4b")
    LanguageModel.create!(backend: edge_backend, name: "llama3:8b")
    LanguageModel.create!(backend: @backend, name: "llama3:8b")
    gemma = model.language_model_family
    llama = LanguageModelFamily.find_by!(name: "llama3")

    edge_backend.destroy!

    assert_not LanguageModel.exists?(model.id)
    assert_not LanguageModelFamily.exists?(gemma.id)
    assert LanguageModelFamily.exists?(llama.id)
  end
end
