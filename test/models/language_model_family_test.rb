require "test_helper"

class LanguageModelFamilyTest < ActiveSupport::TestCase
  test "requires a unique name" do
    LanguageModelFamily.create!(name: "Gemma 3")

    blank = LanguageModelFamily.new(name: "")
    assert_not blank.valid?
    assert_includes blank.errors[:name], "can't be blank"

    duplicate = LanguageModelFamily.new(name: "Gemma 3")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "groups models across backends" do
    family = LanguageModelFamily.create!(name: "Gemma 3")
    system_backend = Backend.ensure_system_default!
    edge_backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")
    family.language_models.create!(backend: system_backend, name: "gemma3:4b")
    family.language_models.create!(backend: system_backend, name: "gemma3:12b")
    family.language_models.create!(backend: edge_backend, name: "gemma3:4b-rk3588")

    assert_equal 3, family.language_models.count
    assert_equal [ system_backend, edge_backend ].to_set, family.backends.to_set
  end

  test "cannot be destroyed while it has models" do
    family = LanguageModelFamily.create!(name: "Gemma 3")
    family.language_models.create!(backend: Backend.ensure_system_default!, name: "gemma3:4b")

    assert_not family.destroy
    assert LanguageModelFamily.exists?(family.id)
  end
end
