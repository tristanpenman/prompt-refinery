require "test_helper"

class BackendTest < ActiveSupport::TestCase
  test "rejects an unsupported adapter change on a persisted backend" do
    backend = Backend.create!(name: "Edge", base_url: "http://edge.test")
    assert_not backend.update(adapter: "unsupported")
    assert_includes backend.errors[:adapter], "cannot be changed; create another backend to switch providers"
  end

  test "rejects an unsupported adapter for a system backend" do
    backend = Backend.new(name: "System", adapter: "unsupported", base_url: "http://edge.test", system: true)
    assert_not backend.valid?
    assert_includes backend.errors[:adapter], "must be ollama for the system backend"
  end

  test "Bedrock derives its URL from the deployment region and ignores custom endpoints" do
    with_aws_region(" us-east-1 ") do
      backend = Backend.create!(name: "AWS", adapter: "bedrock", base_url: "http://ollama:11434")
      assert_equal "https://bedrock-runtime.us-east-1.amazonaws.com", backend.base_url
      assert_equal({ adapter: "bedrock", base_url: backend.base_url }, backend.inference_configuration)

      with_aws_region("cn-north-1") do
        assert_equal "https://bedrock-runtime.cn-north-1.amazonaws.com.cn", backend.inference_configuration[:base_url]
        backend.update!(base_url: "https://custom.test")
        assert_equal "https://bedrock-runtime.cn-north-1.amazonaws.com.cn", backend.base_url
      end
    end
  end

  test "Bedrock requires a valid AWS_REGION but Ollama does not" do
    [ nil, "", " ", "https://custom.test" ].each do |region|
      with_aws_region(region) do
        backend = Backend.new(name: "AWS", adapter: "bedrock", base_url: "http://ignored.test")
        assert_not backend.valid?
        assert_match(/AWS_REGION/, backend.errors.full_messages.join)
        assert_nil backend.base_url
        assert Backend.new(name: "Ollama", base_url: "http://ollama.test").valid?
      end
    end
  end

  test "persisted backends cannot switch adapters" do
    with_aws_region("us-east-1") do
      backend = Backend.create!(name: "Edge", base_url: "http://edge.test")
      assert_not backend.update(adapter: "bedrock")
      assert_includes backend.errors[:adapter], "cannot be changed; create another backend to switch providers"

      backend = Backend.create!(name: "AWS", adapter: "bedrock")
      assert_not backend.update(adapter: "ollama", base_url: "http://edge.test")
    end
  end

  test "a system backend must use Ollama" do
    with_aws_region("us-east-1") do
      backend = Backend.new(name: "System AWS", adapter: "bedrock", system: true)
      assert_not backend.valid?
      assert_includes backend.errors[:adapter], "must be ollama for the system backend"
    end
  end

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

  test "system backend can be disabled but cannot be demoted or destroyed" do
    backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")

    assert backend.update(enabled: false)
    assert_not backend.enabled?
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
    backend.update!(enabled: false)
    same_backend = Backend.ensure_system_default!(base_url: "http://ollama-two:11434///")

    assert_equal backend.id, same_backend.id
    assert_equal "http://ollama-two:11434", same_backend.base_url
    assert_not same_backend.enabled?
    assert_equal "ollama", same_backend.adapter
    assert_equal 1, Backend.where(system: true).count
  end
end
