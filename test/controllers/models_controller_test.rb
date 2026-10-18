require "test_helper"

class ModelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @backend = Backend.ensure_system_default!
  end

  teardown do
    ModelsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists models returned by Ollama" do
    models = [
      {
        "name" => "gemma3:4b",
        "size" => 3_300_000_000,
        "details" => { "family" => "gemma3", "parameter_size" => "4.3B", "quantization_level" => "Q4_K_M" }
      }
    ]
    ModelsController.client_factory = client_factory(models:)

    get models_path

    assert_response :success
    assert_select ".models-page > header" do
      assert_select ".eyebrow", text: "Prompt Refinery"
      assert_select "h1", text: "Available models"
      assert_select "p", text: "Models currently available from enabled inference backends."
    end
    assert_select "h2", text: "gemma3:4b"
    assert_select ".model-backend", text: "Backend: Local Ollama"
    assert_select "li", text: /gemma3 · 4.3B · Q4_K_M/
    assert_select "a[href=?]", prompt_path(model: "gemma3:4b", backend_id: @backend.id), text: "Select"
    assert_select "a[href=?]", evaluate_path(model: "gemma3:4b", backend_id: @backend.id), text: "Evaluate"
    language_model = @backend.language_models.find_by!(name: "gemma3:4b")
    assert_select ".model-family", text: "Family: gemma3"
    assert_select "a[href=?]", edit_model_path(language_model), text: "Edit"
  end

  test "records discovered models once per backend" do
    ModelsController.client_factory = client_factory(models: [ { "name" => "gemma3:4b" } ])

    get models_path
    get models_path

    assert_equal [ "gemma3:4b" ], @backend.language_models.pluck(:name)
  end

  test "edits a model's family" do
    language_model = LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    LanguageModelFamily.create!(name: "Gemma")

    get edit_model_path(language_model)

    assert_response :success
    assert_select "h1", text: "Edit gemma3:4b"
    assert_select "form[action=?]", model_path(language_model)
    assert_select "input[name='language_model[language_model_family_name]'][value='gemma3']"
    assert_select "datalist option[value='Gemma']"

    patch model_path(language_model), params: { language_model: { language_model_family_name: "Gemma" } }

    assert_redirected_to models_path
    assert_equal "Gemma", language_model.reload.language_model_family.name
  end

  test "creates a new family when editing a model" do
    language_model = LanguageModel.create!(backend: @backend, name: "gemma3:4b")

    patch model_path(language_model), params: { language_model: { language_model_family_name: " Gemma 3 " } }

    assert_redirected_to models_path
    assert_equal "Gemma 3", language_model.reload.language_model_family.name
  end

  test "restores the derived family when the family is cleared" do
    family = LanguageModelFamily.create!(name: "Gemma")
    language_model = LanguageModel.create!(backend: @backend, language_model_family: family, name: "gemma3:4b")

    patch model_path(language_model), params: { language_model: { language_model_family_name: "" } }

    assert_redirected_to models_path
    assert_equal "gemma3", language_model.reload.language_model_family.name
  end

  test "re-renders the form when the model cannot be saved" do
    language_model = LanguageModel.create!(backend: @backend, name: ":latest", language_model_family: LanguageModelFamily.create!(name: "Unknown"))

    patch model_path(language_model), params: { language_model: { language_model_family_name: "" } }

    assert_response :unprocessable_content
    assert_select ".form-error", text: /Language model family must exist/
  end

  test "reports an Ollama connection error" do
    ModelsController.client_factory = client_factory(error: "Could not connect to Ollama")

    get models_path

    assert_response :success
    assert_select "[role=alert]", text: /Local Ollama is unavailable.*Could not connect to Ollama/m
  end

  test "lists models from all enabled backends and refreshes them on every load" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    disabled = Backend.create!(name: "Disabled", base_url: "http://disabled.test:8080", enabled: false)
    calls = Hash.new(0)
    responses = {
      @backend.id => [ { "name" => "local-model" } ],
      edge.id => [ { "name" => "edge-model" } ]
    }
    ModelsController.client_factory = changing_client_factory(calls:, responses:)

    get models_path

    assert_select "h2", text: "local-model"
    assert_select "h2", text: "edge-model"
    assert_select ".model-backend", text: "Backend: Local Ollama"
    assert_select ".model-backend", text: "Backend: RK3588"

    responses[edge.id] = [ { "name" => "updated-edge-model" } ]
    get models_path

    assert_select "h2", text: "updated-edge-model"
    assert_select "h2", text: "edge-model", count: 0
    assert_equal 2, calls[@backend.id]
    assert_equal 2, calls[edge.id]
    assert_not calls.key?(disabled.id)
  end

  test "keeps models from available backends when another backend fails" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    factory = Object.new
    factory.define_singleton_method(:for) do |backend|
      Object.new.tap do |client|
        client.define_singleton_method(:models) do
          raise Ollama::Client::Error, "connection refused" if backend == edge

          [ { "name" => "local-model" } ]
        end
      end
    end
    ModelsController.client_factory = factory

    get models_path

    assert_select "h2", text: "local-model"
    assert_select "[role=alert]", text: /RK3588 is unavailable.*connection refused/m
  end

  private

  def client_factory(models: nil, error: nil)
    client = Object.new
    client.define_singleton_method(:models) do
      raise Ollama::Client::Error, error if error

      models
    end
    Object.new.tap { |factory| factory.define_singleton_method(:for) { |_backend| client } }
  end

  def changing_client_factory(calls:, responses:)
    Object.new.tap do |factory|
      factory.define_singleton_method(:for) do |backend|
        Object.new.tap do |client|
          client.define_singleton_method(:models) do
            calls[backend.id] += 1
            responses.fetch(backend.id)
          end
        end
      end
    end
  end
end
