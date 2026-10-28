# Plan

The goal of this project is to build a small local-first application for prompt engineering against models served by Ollama. Users iterate on a single prompt, evaluate each revision against a suite of test cases, review and score the generated responses, and use a stronger teacher model to refine the prompt for a weaker student model.

## Prompts

- Duplicate prompts.
- Preview the fully rendered prompt for a chosen test case before execution.

## Test suites

- ~~Import test cases from a CSV upload: the header row names the variables, and each subsequent row becomes a test case.~~
- Rename a test suite variable without discarding its values. Renaming currently counts as removing one variable and adding another.
- Keep the entered values when adding a test case fails validation.
- Export a test suite's current test cases as CSV, with a header row naming the variables. This differs from downloading the original CSV of an imported test suite.

## CSV imports

- ~~Reject trials for provisional test suites in `Trial` validations, not only by hiding them from the trial form.~~
- ~~Make `TestSuiteRevision.capture!` refuse provisional test suites. `Trial.create_for!` already rolls back the revision when a trial is rejected, so this only guards direct calls to `capture!`.~~
- ~~Document CSV imports in the README, and optionally add a sample CSV to the seed demo data.~~
- ~~Prevent provisional test suites from being archived.~~
- Refuse test case changes for provisional test suites in `TestCasesController`.
- Redirect the revision history of a provisional test suite to its import preview.
- Discard abandoned imports with a recurring job that destroys provisional test suites older than a day and purges their CSV files.
- Link to the uploaded CSV file from the import preview.
- Test that provisional test suites are hidden from the dashboard and the trial form.
- Update `notes/imports.md` to describe the implementation, including the redirect on upload errors and the header-row metadata stored with the CSV file.

## Trial runs

- Add cancellation and more detailed progress reporting.
- Allow failed items to be retried without rerunning successful items.

## Generation settings

- ~~Capture Ollama's token counts and timings for each response.~~
- Choose generation parameters such as temperature, seed, and `num_ctx` when creating a trial.
- Record the parameters on the trial so reruns can be reproduced exactly.

## Review and scoring

- ~~Compare outputs from several trials side by side where they share the same test case.~~
- Review outputs one at a time or in a filterable table.
- Record a numeric score, optional pass/fail decision, and reviewer notes.
- Run automated checks against responses: exact match, regex, and JSON schema.
- Show aggregate metrics for a trial and highlight regressions between prompt revisions.
- Export trial data and reviews as JSON and CSV.

## Amazon Bedrock

Implementation details: [notes/bedrock.md](notes/bedrock.md).

- Add shared inference errors and completion results, preserving Ollama behavior.
- Add the `bedrock` adapter, region configuration, settings UI, and immutable adapter/region snapshots for trials and refinements.
- Add AWS SDK dependencies and wire env / credentials for both Compose services.
- Document IAM permissions and credential refresh.
- Implement Converse generation with option translation, output limits, response validation, bounded retries, and token/time metrics.
- Support model and inference-profile discovery, explicit invocation IDs, and connection checks without losing catalog entries on discovery failure.
- Add native JSON-schema evaluation and teacher capability checks.
- Test the adapter and full refinement flow with stubbed AWS clients, including reference reuse, automatic iterations, completion conditions, and failures.
- Verify a small live refinement with an Ollama student and Bedrock teacher, and document setup and usage.

## Explicitly deferred

User accounts and multi-user authorization, hosted inference providers beyond Amazon Bedrock, distributed workers, general-purpose automated LLM judging outside of refinement, statistical significance analysis, and managed remote deployment are outside the first release. The data model and service boundaries should avoid preventing these additions later.
