require "test_helper"

class Settings::ModelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @backend = Backend.ensure_system_default!
  end

  teardown do
    Settings::ModelsController.client_factory = Inference::Client
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
    Settings::ModelsController.client_factory = client_factory(models:)

    get settings_models_path

    assert_response :success
    assert_select ".models-page > header" do
      assert_select ".eyebrow", text: "Settings"
      assert_select "h1", text: "Models"
      assert_select "p", text: "Models currently available from enabled inference backends."
    end
    assert_select "h2", text: "gemma3:4b"
    assert_select ".model-backend", text: "Backend: Local Ollama"
    assert_select "li", text: /gemma3 · 4.3B · Q4_K_M/
    assert_select "a[href=?]", prompt_path(model: "gemma3:4b", backend_id: @backend.id), text: "Select"
    assert_select "a[href=?]", evaluate_path(model: "gemma3:4b", backend_id: @backend.id), text: "Evaluate"
    language_model = @backend.language_models.find_by!(name: "gemma3:4b")
    assert_select ".model-family", text: "Family: gemma3"
    assert_select "a[href=?]", edit_settings_model_path(language_model), text: "Edit"
  end

  test "filters models by family" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    Settings::ModelsController.client_factory = changing_client_factory(
      calls: Hash.new(0),
      responses: {
        @backend.id => [ { "name" => "gemma3:4b" }, { "name" => "llama3:8b" } ],
        edge.id => [ { "name" => "gemma3:1b" } ]
      }
    )

    get settings_models_path

    gemma = LanguageModelFamily.find_by!(name: "gemma3")
    assert_select "form.model-filter[action=?][method=get]", settings_models_path do
      assert_select "select[name=family] option", text: "All families"
      assert_select "select[name=family] option[value=?]", gemma.id.to_s, text: "gemma3"
      assert_select "select[name=family] option", text: "llama3"
    end
    assert_select ".model-list li", count: 3

    get settings_models_path(family: gemma.id)

    assert_select ".model-list li", count: 2
    assert_select "h2", text: "gemma3:4b"
    assert_select "h2", text: "gemma3:1b"
    assert_select "h2", text: "llama3:8b", count: 0
    assert_select "select[name=family] option[selected][value=?]", gemma.id.to_s
    assert_select "a[href=?]", settings_models_path, text: "Clear"
  end

  test "ignores an unknown family filter" do
    Settings::ModelsController.client_factory = client_factory(models: [ { "name" => "gemma3:4b" } ])

    get settings_models_path(family: "missing")

    assert_select ".model-list li", count: 1
    assert_select "a", text: "Clear", count: 0
  end

  test "records discovered models once per backend" do
    Settings::ModelsController.client_factory = client_factory(models: [ { "name" => "gemma3:4b" } ])

    get settings_models_path
    get settings_models_path

    assert_equal [ "gemma3:4b" ], @backend.language_models.pluck(:name)
  end

  test "edits a model's family" do
    language_model = LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    LanguageModelFamily.create!(name: "Gemma")

    get edit_settings_model_path(language_model)

    assert_response :success
    assert_select "h1", text: "Edit gemma3:4b"
    assert_select "form[action=?]", settings_model_path(language_model)
    assert_select "input[name='language_model[language_model_family_name]'][value='gemma3']"
    assert_select "datalist option[value='Gemma']"

    patch settings_model_path(language_model), params: { language_model: { language_model_family_name: "Gemma" } }

    assert_redirected_to settings_models_path
    assert_equal "Gemma", language_model.reload.language_model_family.name
  end

  test "creates a new family when editing a model" do
    language_model = LanguageModel.create!(backend: @backend, name: "gemma3:4b")

    patch settings_model_path(language_model), params: { language_model: { language_model_family_name: " Gemma 3 " } }

    assert_redirected_to settings_models_path
    assert_equal "Gemma 3", language_model.reload.language_model_family.name
  end

  test "restores the derived family when the family is cleared" do
    family = LanguageModelFamily.create!(name: "Gemma")
    language_model = LanguageModel.create!(backend: @backend, language_model_family: family, name: "gemma3:4b")

    patch settings_model_path(language_model), params: { language_model: { language_model_family_name: "" } }

    assert_redirected_to settings_models_path
    assert_equal "gemma3", language_model.reload.language_model_family.name
  end

  test "re-renders the form when the model cannot be saved" do
    language_model = LanguageModel.create!(backend: @backend, name: ":latest", language_model_family: LanguageModelFamily.create!(name: "Unknown"))

    patch settings_model_path(language_model), params: { language_model: { language_model_family_name: "" } }

    assert_response :unprocessable_content
    assert_select ".form-error", text: /Language model family must exist/
  end

  test "reports an Ollama connection error" do
    Settings::ModelsController.client_factory = client_factory(error: "Could not connect to Ollama")

    get settings_models_path

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
    Settings::ModelsController.client_factory = changing_client_factory(calls:, responses:)

    get settings_models_path

    assert_select "h2", text: "local-model"
    assert_select "h2", text: "edge-model"
    assert_select ".model-backend", text: "Backend: Local Ollama"
    assert_select ".model-backend", text: "Backend: RK3588"

    responses[edge.id] = [ { "name" => "updated-edge-model" } ]
    get settings_models_path

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
    Settings::ModelsController.client_factory = factory

    get settings_models_path

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
