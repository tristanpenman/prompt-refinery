require "test_helper"

class TrialsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @collection = Collection.create!(name: "Examples")
    @collection.prompts.create!(name: "First", template: "Hello", position: 0)
    TrialsController.ollama_client_class = available_models_client
  end

  teardown do
    TrialsController.ollama_client_class = ::Ollama::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists trials and creation options" do
    trial = create_trial(collection: @collection)

    get trials_path

    assert_response :success
    assert_select "option", text: "Examples"
    assert_select "option", text: "gemma3:4b"
    assert_select "section.editor-card.trial-list" do
      assert_select "h2", text: "Previous trials"
      assert_select "table"
    end
    assert_select "a[href=?]", trial_path(trial), text: "Examples"
    assert_select "tr", text: /Examples\s+r1\s+gemma3:4b/
  end

  test "creates response records and enqueues the trial" do
    assert_enqueued_with(job: TrialExecutionJob) do
      assert_difference [ "Trial.count", "Response.count" ], 1 do
        post trials_path, params: { trial: { collection_id: @collection.id, model: "gemma3:4b" } }
      end
    end

    trial = Trial.last
    assert_redirected_to trial
    assert_equal @collection.prompts.ids, trial.responses.pluck(:prompt_id)
  end

  test "shows trial responses" do
    created_at = Time.zone.local(2026, 10, 16, 14, 30)
    trial = create_trial(collection: @collection, status: :completed, created_at: created_at)
    trial.responses.first.update!(status: :completed, content: "Generated response")

    get trial_path(trial)

    assert_response :success
    assert_select ".trial-heading" do
      assert_select "h1", text: "Examples"
    end
    assert_select ".status.status--completed", text: "Completed"
    assert_select "p", text: "Revision: 1"
    assert_select "time[datetime=?]", created_at.iso8601, text: created_at.to_fs(:long)
    assert_select "h3", text: /First r1/
    assert_select ".response-prompt", text: /Prompt\s+Hello/
    assert_select ".trial-responses details", count: 0
    assert_select ".result-content", text: /Generated response/
  end

  private

  def available_models_client
    Class.new do
      def models
        [ { "name" => "gemma3:4b" } ]
      end
    end
  end
end
