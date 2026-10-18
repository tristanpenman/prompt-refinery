require "test_helper"

class BackendTest < ActiveSupport::TestCase
  test "normalizes whitespace and trailing slashes from the base URL" do
    backend = Backend.create!(name: "Edge board", base_url: "  http://edge-board.local:8080/ollama///  ")

    assert_equal "http://edge-board.local:8080/ollama", backend.base_url
  end

  test "accepts HTTP and HTTPS URLs with optional path prefixes" do
    assert Backend.new(name: "HTTP", base_url: "http://ollama:11434").valid?
    assert Backend.new(name: "HTTPS", base_url: "https://models.example.test/ollama").valid?
  end

  test "rejects invalid or unsafe base URLs" do
    invalid_urls = {
      "ftp://models.example.test" => "must use HTTP or HTTPS",
      "http:///api" => "must include a host",
      "http://user:secret@models.example.test" => "must not include credentials",
      "http://models.example.test?token=secret" => "must not include a query",
      "http://models.example.test#fragment" => "must not include a fragment",
      "not a URL" => "is not a valid URL"
    }

    invalid_urls.each do |url, error|
      backend = Backend.new(name: url, base_url: url)

      assert_not backend.valid?, "Expected #{url.inspect} to be invalid"
      assert_includes backend.errors[:base_url], error
    end
  end

  test "requires a unique name and a supported adapter" do
    Backend.create!(name: "Edge board", base_url: "http://edge-one.local:8080")

    duplicate = Backend.new(name: "Edge board", base_url: "http://edge-two.local:8080", adapter: "custom")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
    assert_includes duplicate.errors[:adapter], "is not included in the list"
  end

  test "system backend must remain enabled and cannot be demoted or destroyed" do
    backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")

    assert_not backend.update(enabled: false)
    assert_includes backend.errors[:enabled], "must be enabled for the system backend"
    assert_not backend.update(system: false)
    assert_includes backend.errors[:system], "cannot be removed from the system backend"
    assert_not backend.destroy
    assert_includes backend.errors[:base], "The system backend cannot be deleted"
    assert Backend.exists?(backend.id)
  end

  test "ordinary backends can be disabled and destroyed" do
    backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")

    backend.update!(enabled: false)
    backend.destroy!

    assert_not Backend.exists?(backend.id)
  end

  test "ensuring the system default is idempotent and updates its configured URL" do
    backend = Backend.ensure_system_default!(base_url: "http://ollama-one:11434/")
    same_backend = Backend.ensure_system_default!(base_url: "http://ollama-two:11434///")

    assert_equal backend.id, same_backend.id
    assert_equal "http://ollama-two:11434", same_backend.base_url
    assert same_backend.enabled?
    assert_equal "ollama", same_backend.adapter
    assert_equal 1, Backend.where(system: true).count
  end
end
