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

  test "lists recorded models without contacting backends" do
    Settings::ModelsController.client_factory = unreachable_client_factory
    language_model = LanguageModel.create!(
      backend: @backend,
      name: "gemma3:4b",
      size: 3_300_000_000,
      details: { "family" => "gemma3", "parameter_size" => "4.3B", "quantization_level" => "Q4_K_M" }
    )

    get settings_models_path

    assert_response :success
    assert_select ".models-page > header" do
      assert_select ".eyebrow", text: "Settings"
      assert_select "h1", text: "Models"
      assert_select "p", text: "Models found on inference backends. A model stays listed as unavailable after it is removed from its backend."
    end
    assert_select "h3", text: "gemma3:4b"
    assert_select ".model-backend", text: "Backend: Local Ollama"
    assert_select ".model-family", text: "Family: gemma3"
    assert_select "li", text: /gemma3 · 4.3B · Q4_K_M/
    assert_select "li span", text: "3.07 GB"
    assert_select ".model-refreshed time[datetime=?]", language_model.refreshed_at.iso8601, text: "less than a minute ago"
    assert_select "a[href=?]", playground_path(model: "gemma3:4b", backend_id: @backend.id), text: "Select"
    assert_select "a[href=?]", evaluate_path(model: "gemma3:4b", backend_id: @backend.id), text: "Evaluate"
    assert_select "a[href=?]", edit_settings_model_path(language_model), text: "Edit"
  end

  test "shows a refresh panel above the models" do
    get settings_models_path

    assert_select ".models-page > header + section.model-refresh" do
      assert_select "h2", text: "Refresh models"
      assert_select "form[action=?][method=post] button", refresh_settings_models_path, text: "Refresh"
    end
    assert_select ".notice h2", text: "No models recorded"
  end

  test "marks models on disabled backends and doesn't offer to use them" do
    disabled = Backend.create!(name: "Old server", base_url: "http://old.test:11434", enabled: false)
    language_model = LanguageModel.create!(backend: disabled, name: "llama3:8b")

    get settings_models_path

    assert_select ".model-backend", text: /Backend: Old server\s+Disabled/
    assert_select "a", text: "Select", count: 0
    assert_select "a", text: "Evaluate", count: 0
    assert_select "a[href=?]", edit_settings_model_path(language_model), text: "Edit"
  end

  test "groups unavailable models beneath available ones and only offers to edit them" do
    available = LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    unavailable = LanguageModel.create!(backend: @backend, name: "llama3:8b", available: false)

    get settings_models_path

    assert_select ".model-group", count: 2
    assert_select ".model-group:first-of-type" do
      assert_select "h2", text: "Available"
      assert_select ".model-list li h3", text: "gemma3:4b"
      assert_select ".model-list li", count: 1
      assert_select "a[href=?]", playground_path(model: "gemma3:4b", backend_id: @backend.id), text: "Select"
      assert_select "a[href=?]", evaluate_path(model: "gemma3:4b", backend_id: @backend.id), text: "Evaluate"
      assert_select "a[href=?]", edit_settings_model_path(available), text: "Edit"
    end
    assert_select ".model-group:last-of-type" do
      assert_select "h2", text: "Unavailable"
      assert_select ".model-list li h3", text: "llama3:8b"
      assert_select ".model-list li", count: 1
      assert_select "a", text: "Select", count: 0
      assert_select "a", text: "Evaluate", count: 0
      assert_select "a[href=?]", edit_settings_model_path(unavailable), text: "Edit"
    end
  end

  test "leaves out the unavailable group when every model is available" do
    LanguageModel.create!(backend: @backend, name: "gemma3:4b")

    get settings_models_path

    assert_select ".model-group", count: 1
    assert_select ".model-group h2", text: "Available"
  end

  test "filters models by family" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    LanguageModel.create!(backend: @backend, name: "gemma3:4b")
    LanguageModel.create!(backend: @backend, name: "llama3:8b")
    LanguageModel.create!(backend: edge, name: "gemma3:1b")

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
    assert_select "h3", text: "gemma3:4b"
    assert_select "h3", text: "gemma3:1b"
    assert_select "h3", text: "llama3:8b", count: 0
    assert_select "select[name=family] option[selected][value=?]", gemma.id.to_s
    assert_select "a[href=?]", settings_models_path, text: "Clear"
  end

  test "ignores an unknown family filter" do
    LanguageModel.create!(backend: @backend, name: "gemma3:4b")

    get settings_models_path(family: "missing")

    assert_select ".model-list li", count: 1
    assert_select "a", text: "Clear", count: 0
  end

  test "refresh records new models and their families from every enabled backend" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    disabled = Backend.create!(name: "Disabled", base_url: "http://disabled.test:8080", enabled: false)
    calls = Hash.new(0)
    Settings::ModelsController.client_factory = changing_client_factory(calls:, responses: {
      @backend.id => [
        { "name" => "gemma3:4b", "size" => 3_300_000_000, "details" => { "parameter_size" => "4.3B" } },
        { "name" => "qwen2.5:7b" }
      ],
      edge.id => [ { "name" => "gemma3:1b" } ]
    })
    LanguageModelFamily.create!(name: "gemma3")

    assert_difference -> { LanguageModel.count } => 3, -> { LanguageModelFamily.count } => 1 do
      post refresh_settings_models_path
    end

    assert_redirected_to settings_models_path
    assert_equal "Checked 2 backends and found 3 models, including 3 new.", flash[:notice]
    assert_nil flash[:alert]
    gemma = @backend.language_models.find_by!(name: "gemma3:4b")
    assert_equal "gemma3", gemma.language_model_family.name
    assert_equal 3_300_000_000, gemma.size
    assert_equal({ "parameter_size" => "4.3B" }, gemma.details)
    assert_equal "qwen2.5", @backend.language_models.find_by!(name: "qwen2.5:7b").language_model_family.name
    assert_equal [ "gemma3:1b" ], edge.language_models.pluck(:name)
    assert_not calls.key?(disabled.id)
  end

  test "large Bedrock catalogs fit in the session cookie and persist every model" do
    with_aws_region("us-east-1") do
      @backend.update!(enabled: false)
      bedrock = Backend.create!(name: "AWS", adapter: "bedrock")
      models = 113.times.map do |index|
        { "name" => "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-sonnet-#{index}-v1:0" }
      end
      Settings::ModelsController.client_factory = client_factory(models:)

      post refresh_settings_models_path

      assert_redirected_to settings_models_path
      assert_equal "Checked 1 backend and found 113 models, including 113 new.", flash[:notice]
      assert_equal 113, bedrock.language_models.count
      follow_redirect!
      assert_response :success
      assert_select ".model-list li h3", count: 113
    end
  end

  test "refresh keeps models that are no longer available and updates known ones" do
    family = LanguageModelFamily.create!(name: "Gemma")
    known, removed = travel_to(3.days.ago) do
      [
        LanguageModel.create!(backend: @backend, name: "gemma3:4b", language_model_family: family, size: 1),
        LanguageModel.create!(backend: @backend, name: "llama3:8b")
      ]
    end
    removed_refreshed_at = removed.refreshed_at
    Settings::ModelsController.client_factory = client_factory(models: [ { "name" => "gemma3:4b", "size" => 2 } ])

    assert_no_difference -> { LanguageModel.count } do
      post refresh_settings_models_path
    end

    assert_equal "Checked 1 backend and found 1 model. No new models.", flash[:notice]
    assert_equal 2, known.reload.size
    assert_equal family, known.language_model_family
    assert_in_delta Time.current, known.refreshed_at, 5.seconds
    assert known.available
    assert_equal removed_refreshed_at, removed.reload.refreshed_at
    assert_not removed.available

    follow_redirect!
    assert_select "li", text: /gemma3:4b.*Last refreshed\s+less than a minute ago/m
    assert_select "li", text: /llama3:8b.*Last refreshed\s+3 days ago/m
  end

  test "refresh updates when a model was last seen even if nothing else changed" do
    language_model = travel_to(1.day.ago) { LanguageModel.create!(backend: @backend, name: "gemma3:4b") }
    Settings::ModelsController.client_factory = client_factory(models: [ { "name" => "gemma3:4b" } ])

    post refresh_settings_models_path

    assert_in_delta Time.current, language_model.reload.refreshed_at, 5.seconds
  end

  test "refresh marks a model available again when it reappears" do
    language_model = LanguageModel.create!(backend: @backend, name: "gemma3:4b", available: false)
    Settings::ModelsController.client_factory = client_factory(models: [ { "name" => "gemma3:4b" } ])

    post refresh_settings_models_path

    assert language_model.reload.available
  end

  test "refresh reports backends that couldn't be checked and keeps the rest" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    factory = Object.new
    factory.define_singleton_method(:for) do |backend|
      Object.new.tap do |client|
        client.define_singleton_method(:models) do
          raise Inference::Error, "connection refused" if backend == edge

          [ { "name" => "local-model" } ]
        end
      end
    end
    Settings::ModelsController.client_factory = factory

    post refresh_settings_models_path

    assert_equal "Checked 1 backend and found 1 model, including 1 new.", flash[:notice]
    assert_equal "Could not check RK3588: connection refused", flash[:alert]
    assert @backend.language_models.exists?(name: "local-model")
  end

  test "refresh leaves models available on backends that couldn't be checked" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    edge_model = LanguageModel.create!(backend: edge, name: "qwen3:1.7b")
    factory = Object.new
    factory.define_singleton_method(:for) do |backend|
      Object.new.tap do |client|
        client.define_singleton_method(:models) do
          raise Inference::Error, "connection refused" if backend == edge

          []
        end
      end
    end
    Settings::ModelsController.client_factory = factory

    post refresh_settings_models_path

    assert edge_model.reload.available
  end

  test "refresh without enabled backends" do
    @backend.update!(enabled: false)
    Settings::ModelsController.client_factory = unreachable_client_factory

    post refresh_settings_models_path

    assert_redirected_to settings_models_path
    assert_equal "There are no enabled backends to check.", flash[:alert]
  end

  test "refresh requires authentication" do
    delete logout_path

    post refresh_settings_models_path

    assert_redirected_to login_path(return_to: refresh_settings_models_path)
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

  private

  def client_factory(models:)
    client = Object.new
    client.define_singleton_method(:models) { models }
    Object.new.tap { |factory| factory.define_singleton_method(:for) { |_backend| client } }
  end

  def unreachable_client_factory
    Object.new.tap { |factory| factory.define_singleton_method(:for) { |_backend| raise "backends should not be contacted" } }
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
