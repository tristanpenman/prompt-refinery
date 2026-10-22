# Builds the request asking the teacher to evaluate an iteration's student
# trial against the reference trial, and checks the teacher's reply.
class RefinementEvaluation
  Invalid = Class.new(StandardError)
  Result = Data.define(:case_evaluations, :agreement, :summary, :change_summary, :proposed_template, :done)

  FORMAT = {
    type: "object",
    properties: {
      cases: {
        type: "array",
        items: {
          type: "object",
          properties: {
            case: { type: "integer" },
            verdict: { type: "string", enum: PromptRefinementIteration::VERDICTS },
            notes: { type: "string" }
          },
          required: %w[case verdict notes]
        }
      },
      summary: { type: "string" },
      changes: { type: "string" },
      done: { type: "boolean" },
      prompt: { type: "string" }
    },
    required: %w[cases summary changes done prompt]
  }.freeze

  # Delimiters that models sometimes copy from the request into the proposed
  # template, as opening and closing patterns.
  TEMPLATE_WRAPPERS = [
    [ /\A---[ \t]*\n/, /\n[ \t]*---\z/ ],
    [ /\A<template>\s*/, /\s*<\/template>\z/ ]
  ].freeze

  # Removes delimiters that wrap the whole template, however deeply nested.
  def self.unwrap_template(template)
    template = template.strip
    loop do
      opening, closing = TEMPLATE_WRAPPERS.find { |opening, closing| template.match?(opening) && template.match?(closing) }
      return template unless opening

      template = template.sub(opening, "").sub(closing, "").strip
    end
  end

  def initialize(refinement:, iteration:)
    @refinement = refinement
    @iteration = iteration
    @test_cases = refinement.test_suite_revision.test_suite_revision_cases.includes(:test_case_revision).to_a
    @reference_responses = refinement.reference_trial.responses.index_by(&:test_suite_revision_case_id)
    @student_responses = iteration.student_trial.responses.index_by(&:test_suite_revision_case_id)
  end

  def prompt
    PromptTemplate.new(refinement.instructions).render(
      "current_prompt" => iteration.prompt_revision.template,
      "variables" => variables.join(", "),
      "cases" => cases,
      "history" => history
    ) + "\n\n#{reply_instructions}"
  end

  # The request to send after a reply was rejected.
  def retry_prompt(reason)
    "#{prompt}\n\nYour previous reply was rejected: #{reason}. Reply again, following the format exactly."
  end

  def parse(reply)
    data = JSON.parse(reply)
    raise Invalid, "the reply is not a JSON object" unless data.is_a?(Hash)

    evaluations = parse_cases(data["cases"])
    summary, changes, proposed_template = %w[summary changes prompt].map do |key|
      data[key].is_a?(String) ? data[key].strip : raise(Invalid, "\"#{key}\" must be a string")
    end
    proposed_template = self.class.unwrap_template(proposed_template)
    raise Invalid, "\"prompt\" must not be empty" if proposed_template.empty?
    raise Invalid, "\"done\" must be true or false" unless [ true, false ].include?(data["done"])

    unknown = PromptTemplate.new(proposed_template).variables - variables
    if unknown.any?
      raise Invalid, "the prompt uses #{"variable".pluralize(unknown.size)} that the test suite doesn't have: #{unknown.to_sentence}"
    end

    Result.new(
      case_evaluations: evaluations,
      agreement: agreement(evaluations.values),
      summary: summary,
      change_summary: changes,
      proposed_template: proposed_template,
      done: data["done"]
    )
  rescue JSON::ParserError
    raise Invalid, "the reply is not valid JSON"
  end

  private

  attr_reader :refinement, :iteration, :test_cases, :reference_responses, :student_responses

  def variables
    refinement.test_suite_revision.variables
  end

  def cases
    test_cases.each.with_index(1).map do |test_case, number|
      values = test_case.test_case_revision.values
      <<~CASE.strip
        <test_case number="#{number}">
        Variables:
        #{variables.map { |name| "- #{name}: #{values[name]}" }.join("\n")}
        <reference_output>
        #{output(reference_responses[test_case.id])}
        </reference_output>
        <student_output>
        #{output(student_responses[test_case.id])}
        </student_output>
        </test_case>
      CASE
    end.join("\n\n")
  end

  def output(response)
    response&.completed? ? response.content : "(No output: the request failed.)"
  end

  def history
    earlier = refinement.iterations.completed.where(number: ...iteration.number).includes(:prompt_revision)
    return "None. This is the first attempt." if earlier.empty?

    earlier.map do |previous|
      "Iteration #{previous.number} (prompt r#{previous.prompt_revision.version}): " \
        "agreement #{(previous.agreement * 100).round}%. #{previous.summary} Changes made: #{previous.change_summary}"
    end.join("\n")
  end

  def reply_instructions
    <<~TEXT.strip
      Reply with a JSON object only, with these keys:
      - "cases": one entry per test case, each with "case" (the test case number), "verdict" ("match", "partial", or "miss"), and "notes" (a short explanation)
      - "summary": the student's main shortcomings
      - "changes": what you changed in the template, and why
      - "done": true if the template can't be improved further, otherwise false
      - "prompt": the complete improved template only, without the <template> tags or any other delimiters around it
    TEXT
  end

  # Returns verdicts keyed by test suite revision case id. A case whose student
  # response failed is always a miss.
  def parse_cases(entries)
    unless entries.is_a?(Array) && entries.size == test_cases.size
      raise Invalid, "\"cases\" must have exactly #{test_cases.size} #{"entry".pluralize(test_cases.size)}"
    end

    entries.each_with_object({}) do |entry, evaluations|
      raise Invalid, "each entry in \"cases\" must be an object" unless entry.is_a?(Hash)

      number = entry["case"]
      test_case = number.is_a?(Integer) && number.positive? ? test_cases[number - 1] : nil
      raise Invalid, "case numbers must be from 1 to #{test_cases.size}" unless test_case
      raise Invalid, "test case #{number} is listed more than once" if evaluations.key?(test_case.id.to_s)
      unless PromptRefinementIteration::VERDICTS.include?(entry["verdict"])
        raise Invalid, "the verdict for test case #{number} must be #{PromptRefinementIteration::VERDICTS.to_sentence(last_word_connector: ", or ")}"
      end

      notes = entry["notes"].to_s.strip
      if student_responses[test_case.id]&.completed?
        evaluations[test_case.id.to_s] = { "verdict" => entry["verdict"], "notes" => notes }
      else
        evaluations[test_case.id.to_s] = { "verdict" => "miss", "notes" => "The student's request failed." }
      end
    end
  end

  def agreement(evaluations)
    verdicts = evaluations.map { |evaluation| evaluation["verdict"] }
    ((verdicts.count("match") + 0.5 * verdicts.count("partial")) / verdicts.size).round(3)
  end
end
