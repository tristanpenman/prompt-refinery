# Demo data for product demos. This file expects an empty database apart from
# the system backend, so load it with `bin/rails prompt_refinery:demo:reset`
# rather than running it directly.
#
# The data tells a short story: a sentiment prompt and a support-ticket summary
# prompt are each refined after a first, loose revision, then compared across
# a few local models. One trial fails because its model was never pulled.
# A batch of tickets is later imported from a helpdesk CSV export.

require "active_support/testing/time_helpers"

class DemoSeeds
  include ActiveSupport::Testing::TimeHelpers

  MODELS = %w[llama3.2:3b qwen2.5:7b gemma3:4b].freeze

  REVIEWS = [
    "Absolutely love these headphones. The noise cancelling is superb and the battery easily lasts a long-haul flight.",
    "Arrived two weeks late and the box was crushed. The kettle itself works, but I wouldn't order from here again.",
    "Does exactly what it says. Nothing more, nothing less.",
    "Oh great, another charger that stops working after three days. Exactly what I needed.",
    "The fabric is gorgeous but the sizing runs very small. Had to send it back for a larger size.",
    "Customer service replaced my faulty blender within 48 hours, no questions asked. Brilliant.",
    "Cheap plastic, wobbly legs, and the instructions were missing half the steps.",
    "Not bad for the price, though I expected the colours to be more vivid."
  ].freeze

  # Added after the first trial, to catch the sarcasm and misdirection that
  # the loose prompt struggled with.
  TRICKY_REVIEWS = [
    "I wanted to hate this robot vacuum after the setup nightmare, but honestly it's changed my life.",
    "5 stars because the delivery driver was lovely. The actual lamp arrived broken."
  ].freeze

  TICKETS = [
    {
      "subject" => "Charged twice for my subscription",
      "message" => "Hi, I've just checked my bank statement and I've been charged £14.99 twice on 3 October for my Pro subscription. I only have one account. Can you please refund the duplicate payment? Thanks, Priya"
    },
    {
      "subject" => "Locked out after password reset",
      "message" => "I requested a password reset this morning but the link said it had expired when I clicked it about ten minutes later. I tried again three times and now the login page says my account is locked. I have a client presentation at 9am tomorrow and all my slides are in your app. Please help ASAP."
    },
    {
      "subject" => "Order #48213 missing item",
      "message" => "My order arrived today but the charging dock wasn't in the box, only the headset and the cable. The packing slip lists the dock so I think it was just missed. Could you send it out separately? I don't need to return anything else."
    },
    {
      "subject" => "Dark mode?",
      "message" => "Love the app, use it every day. Any chance of a dark mode? I do a lot of work late at night and the white background is pretty harsh. Not urgent at all, just a suggestion!"
    },
    {
      "subject" => "App crashes when uploading photos",
      "message" => "Since the update last week the iPhone app crashes every time I try to upload more than about ten photos at once. Uploading them one at a time works but it takes forever. iPhone 15, iOS 18.1. I've already tried reinstalling."
    },
    {
      "subject" => "Cancel my account and delete my data",
      "message" => "This is the third time this month the sync has failed and I've lost work. I'm done. Cancel my account effective immediately and delete all of my data. I want written confirmation that this has been done under GDPR. Don't bother trying to offer me a discount."
    }
  ].freeze

  SENTIMENT_V1 = <<~TEMPLATE.strip
    Is the following review positive or negative?

    {{review}}
  TEMPLATE

  SENTIMENT_V2 = <<~TEMPLATE.strip
    Classify the sentiment of the product review below.

    Respond with exactly one word: positive, negative, or mixed. Do not explain your answer.

    Review:
    {{review}}
  TEMPLATE

  SUMMARY_V1 = <<~TEMPLATE.strip
    Summarise the following customer support ticket.

    Subject: {{subject}}

    {{message}}
  TEMPLATE

  SUMMARY_V2 = <<~TEMPLATE.strip
    You are a support team lead. Summarise the ticket below for an agent who has not read it.

    Reply in exactly this format:
    Issue: <one sentence>
    Customer wants: <one sentence>
    Sentiment: <calm | frustrated | angry>

    Subject: {{subject}}
    Message:
    {{message}}
  TEMPLATE

  TRIAGE = <<~TEMPLATE.strip
    Assign a priority to this support ticket.

    P1: service unavailable, security, or money taken in error
    P2: customer blocked, but a workaround exists
    P3: questions, feature requests, and minor issues

    Respond with the priority followed by a short reason, for example "P2 – customer cannot export reports".

    Subject: {{subject}}
    {{message}}
  TEMPLATE

  TRANSLATE = <<~TEMPLATE.strip
    Translate this product review into English. If it is already in English, repeat it unchanged.

    {{review}}
  TEMPLATE

  def call
    @backend = Backend.system_default
    MODELS.each { |model| @backend.language_models.find_or_create_by!(name: model) }

    reviews = at(10.days.ago) { create_suite("Product reviews", %w[review], REVIEWS.map { |review| { "review" => review } }) }
    tickets = at(10.days.ago + 1.hour) { create_suite("Support tickets", %w[subject message], TICKETS) }

    sentiment = at(9.days.ago) { Prompt.create!(name: "Positive or negative?", template: SENTIMENT_V1) }
    summary = at(8.days.ago) { Prompt.create!(name: "Summarise customer issue", template: SUMMARY_V1) }

    run_trial(sentiment, reviews, "llama3.2:3b", at: 9.days.ago + 20.minutes, pace: 2.4, outputs: [
      "This review is positive. The customer is very happy with the headphones, especially the noise cancelling and the long battery life.",
      "The sentiment of this review is negative. Although the kettle works, the customer was unhappy with the late delivery and the damaged packaging, and says they would not order again.",
      "This review is neutral to slightly positive. The customer indicates that the product meets their expectations but does not express any particular enthusiasm.",
      "Positive! The reviewer says the charger is \"exactly what I needed\".",
      "This review is mixed. The customer likes the fabric but was disappointed with the sizing, which led them to return the item. Overall I would lean towards negative.",
      "Positive. The reviewer praises the fast replacement from customer service.",
      "Negative",
      "I would classify this review as somewhat positive. The reviewer feels the product is good value, although they had slightly higher expectations for the colours."
    ])

    run_trial(summary, tickets, "llama3.2:3b", at: 8.days.ago + 15.minutes, pace: 5.8, outputs: [
      "The customer, Priya, reports being charged £14.99 twice on 3 October for a Pro subscription, despite only having one account. They are asking for the duplicate payment to be refunded.",
      "The customer requested a password reset, but the reset link had expired by the time they used it. After several more attempts their account is now locked. They need access urgently because they have a client presentation tomorrow morning and their slides are stored in the app.",
      "The customer received order #48213, but the charging dock was missing from the box even though it appears on the packing slip. They would like the dock to be sent separately.",
      "This ticket is a feature request. The customer enjoys using the app every day and would like a dark mode option because they often work late at night. They note that it is not urgent.",
      "Since last week's update, the iPhone app crashes whenever the customer uploads more than around ten photos at once. Uploading photos one at a time still works, but is slow. The customer is using an iPhone 15 with iOS 18.1 and has already tried reinstalling the app.",
      "The customer is frustrated because sync has failed three times this month, causing them to lose work. They want to cancel their account immediately, have all their data deleted, and receive written confirmation under GDPR. They are not interested in any discount offers."
    ])

    at(6.days.ago) { add_cases(reviews, TRICKY_REVIEWS.map { |review| { "review" => review } }) }
    at(6.days.ago + 10.minutes) { sentiment.update!(template: SENTIMENT_V2) }

    run_trial(sentiment, reviews, "llama3.2:3b", at: 6.days.ago + 15.minutes, pace: 0.6, outputs: %w[
      positive negative positive positive mixed positive negative mixed mixed positive
    ])
    run_trial(sentiment, reviews, "qwen2.5:7b", at: 6.days.ago + 18.minutes, pace: 1.1, outputs: %w[
      positive negative positive negative mixed positive negative mixed positive negative
    ])
    run_trial(sentiment, reviews, "gemma3:4b", at: 6.days.ago + 22.minutes, pace: 0.9, outputs: %w[
      Positive Negative Neutral Negative Mixed Positive Negative Mixed Positive Mixed
    ])

    at(5.days.ago) { summary.update!(template: SUMMARY_V2) }

    run_trial(summary, tickets, "llama3.2:3b", at: 5.days.ago + 5.minutes, pace: 2.9, outputs: [
      "Issue: Customer was charged £14.99 twice for one Pro subscription on 3 October.\nCustomer wants: A refund of the duplicate payment.\nSentiment: calm",
      "Issue: Password reset link expired and the account is now locked after repeated attempts.\nCustomer wants: Their account unlocked before a client presentation tomorrow morning.\nSentiment: calm",
      "Issue: The charging dock was missing from order #48213.\nCustomer wants: The dock sent separately.\nSentiment: calm",
      "Issue: Feature request for a dark mode.\nCustomer wants: A dark mode option for working at night.\nSentiment: calm\n\nNote: This is not a support issue and could be forwarded to the product team.",
      "Issue: iPhone app crashes when uploading more than ten photos at once since the latest update.\nCustomer wants: A fix for bulk photo uploads.\nSentiment: frustrated",
      "Issue: Repeated sync failures have caused the customer to lose work.\nCustomer wants: Immediate cancellation, deletion of all data, and written GDPR confirmation.\nSentiment: angry"
    ])
    run_trial(summary, tickets, "qwen2.5:7b", at: 5.days.ago + 12.minutes, pace: 4.7, outputs: [
      "Issue: A single Pro subscription was billed twice (£14.99 on 3 October).\nCustomer wants: The duplicate charge refunded.\nSentiment: calm",
      "Issue: Expired reset links led to the account being locked after several attempts.\nCustomer wants: Urgent access restored before a 9am client presentation tomorrow.\nSentiment: frustrated",
      "Issue: Order #48213 arrived without the charging dock listed on the packing slip.\nCustomer wants: The missing dock shipped separately, with no return needed.\nSentiment: calm",
      "Issue: No dark mode is available in the app.\nCustomer wants: A dark mode added in a future release; not urgent.\nSentiment: calm",
      "Issue: Since last week's update, the iOS app (iPhone 15, iOS 18.1) crashes when uploading more than ~10 photos; reinstalling did not help.\nCustomer wants: Bulk photo uploads to work again.\nSentiment: frustrated",
      "Issue: Sync has failed three times this month, causing data loss.\nCustomer wants: The account cancelled immediately and all data deleted, with written GDPR confirmation and no retention offers.\nSentiment: angry"
    ])

    failure = { error: "Ollama returned HTTP 404" }
    run_trial(summary, tickets, "mistral:7b", at: 4.days.ago, pace: 0.1, outputs: Array.new(TICKETS.size, failure))

    triage = at(3.days.ago) { Prompt.create!(name: "Triage ticket priority", template: TRIAGE) }

    run_trial(triage, tickets, "qwen2.5:7b", at: 2.days.ago, pace: 1.8, outputs: [
      "P1 – customer was charged twice and needs the duplicate payment refunded",
      "P2 – customer is locked out ahead of a deadline; the account can be unlocked manually",
      "P3 – missing accessory from an order; customer only needs it shipped",
      "P3 – feature request for dark mode",
      "P2 – bulk photo uploads crash on iOS; uploading one at a time works",
      "P2 – cancellation and GDPR deletion request from an unhappy customer"
    ])
    run_trial(triage, tickets, "gemma3:4b", at: 2.days.ago + 6.minutes, pace: 1.4, outputs: [
      "**P1** – Duplicate charge on the customer's subscription.",
      "P1 – The customer cannot access their account and has an urgent deadline.",
      "P3 – Missing item from an order.",
      "P3 – Feature request (dark mode).",
      "P2 – App crash when uploading multiple photos; uploading one at a time works.",
      "P2 – Account cancellation and data deletion request."
    ])

    # Imported as the app's preview would, renaming the spreadsheet headers to template variables.
    helpdesk = at(1.day.ago) { import_suite("helpdesk_export.csv") }
    at(1.day.ago + 5.minutes) do
      helpdesk.confirm_import!(name: "Helpdesk export", variable_names: helpdesk.variables.index_with(&:underscore))
    end

    run_trial(triage, helpdesk, "qwen2.5:7b", at: 1.day.ago + 10.minutes, pace: 1.6, outputs: [
      "P3 – invoices need the company name corrected; finance can wait for reissued copies",
      "P2 – invites are failing ahead of new starters joining on Monday",
      "P3 – PDF export cuts off wide tables; exporting to Excel works",
      "P1 – login returns 502 for a whole team while the status page shows no incident"
    ])

    translate = at(7.days.ago) { Prompt.create!(name: "Translate review to English", template: TRANSLATE) }
    at(3.days.ago) { translate.archive! }
  end

  private

  def at(time, &block)
    travel_to(time, &block)
  end

  def create_suite(name, variables, cases)
    TestSuite.create!(name: name, variables: variables).tap { |suite| add_cases(suite, cases) }
  end

  # Creates a provisional test suite from a CSV in db/seeds/files, as if it
  # had been uploaded through the app.
  def import_suite(filename)
    File.open(Rails.root.join("db/seeds/files", filename)) do |io|
      file = ActionDispatch::Http::UploadedFile.new(tempfile: io, filename: filename, type: "text/csv")
      TestSuite.import_csv!(file: file, header_row: true)
    end
  end

  def add_cases(suite, cases)
    offset = suite.test_cases.count
    cases.each_with_index do |values, index|
      suite.test_cases.create!(values: values, position: offset + index)
    end
  end

  # Creates a trial as the app would, then fills in its responses as if a job
  # had run it, spending `pace` seconds on each response.
  def run_trial(prompt, suite, model, at:, pace:, outputs:)
    trial = travel_to(at) { Trial.create_for!(prompt: prompt, test_suite: suite, backend: @backend, model: model) }
    responses = trial.responses.joins(:test_suite_revision_case).order("test_suite_revision_cases.position").to_a
    raise ArgumentError, "#{prompt.name} on #{model} needs #{responses.size} outputs" unless responses.size == outputs.size

    clock = at + 2.seconds
    travel_to(clock) { trial.update!(status: :running, started_at: Time.current) }

    responses.zip(outputs).each do |response, output|
      clock += pace.seconds
      travel_to(clock) do
        if output.is_a?(Hash)
          response.update!(status: :failed, error: output[:error])
        else
          response.update!(status: :completed, content: output)
        end
      end
    end

    travel_to(clock + 1.second) do
      trial.update!(status: trial.responses.failed.exists? ? :failed : :completed, completed_at: Time.current)
    end
  end
end

DemoSeeds.new.call
