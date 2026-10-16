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

  test "does not offer or create a trial for an archived collection" do
    existing_trial = create_trial(collection: @collection)
    @collection.archive!

    get trials_path

    assert_response :success
    assert_select "option", text: "Examples", count: 0
    assert_select "a[href=?]", trial_path(existing_trial), text: "Examples"
    assert_select "tr", text: /Examples\s+Archived\s+r1/

    assert_no_enqueued_jobs do
      assert_no_difference "Trial.count" do
        post trials_path, params: { trial: { collection_id: @collection.id, model: "gemma3:4b" } }
      end
    end

    assert_response :unprocessable_content
  end

  test "does not offer or create a trial for a collection without prompts" do
    empty_collection = Collection.create!(name: "Empty")

    get trials_path

    assert_response :success
    assert_select "option", text: "Examples"
    assert_select "option", text: "Empty", count: 0

    assert_no_enqueued_jobs do
      assert_no_difference "Trial.count" do
        post trials_path, params: { trial: { collection_id: empty_collection.id, model: "gemma3:4b" } }
      end
    end

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Collection must contain at least one prompt/
  end

  test "shows trial responses" do
    created_at = Time.zone.local(2026, 10, 16, 14, 30)
    trial = create_trial(collection: @collection, status: :completed, created_at: created_at)
    trial.responses.first.update!(status: :completed, content: "**Generated** response")

    get trial_path(trial)

    assert_response :success
    assert_select ".trials-page > header" do
      assert_select "h1", text: "Examples"
      assert_select "a", count: 0
    end
    assert_select "section.editor-card" do
      assert_select "h2", text: "Trial details"
      assert_select ".status.status--completed", text: "Completed"
      assert_select "p", text: "Revision: 1"
      assert_select "time[datetime=?]", created_at.iso8601, text: created_at.to_fs(:long)
      assert_select "a[href=?]", compare_trial_path(trial), text: "Compare trial"
    end
    assert_select "h3", text: /First r1/
    assert_select ".response-prompt", text: /Prompt\s+Hello/
    assert_select ".trial-responses details", count: 0
    assert_select ".result-content.markdown-content strong", text: "Generated"
  end

  test "marks the trial title when its collection is archived" do
    trial = create_trial(collection: @collection)
    @collection.archive!

    get trial_path(trial)

    assert_response :success
    assert_select ".trials-page > header h1", text: /Examples/
    assert_select ".trials-page > header h1 .status--archived", text: "Archived"
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
