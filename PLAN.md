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
- Prevent provisional test suites from being archived.
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

- Review outputs one at a time or in a filterable table.
- Record a numeric score, optional pass/fail decision, and reviewer notes.
- Run automated checks against responses: exact match, regex, and JSON schema.
- Compare outputs from several trials side by side where they share the same test case.
- Show aggregate metrics for a trial and highlight regressions between prompt revisions.
- Export trial data and reviews as JSON and CSV.

## Refinement

A refinement exercise uses a teacher model to improve a prompt for a student model:

- Select a student model, a teacher model, a starting prompt revision, and a test suite.
- On the first iteration, create one trial for the student model and one for the teacher model. Each model executes every test case in the suite.
- Once both trials are complete, a separate instance of the teacher model evaluates the outputs and generates a new prompt revision that is expected to close the gap between student and teacher.
- Record each iteration with its trials, the teacher's evaluation, and the resulting prompt revision, so the path from starting prompt to final prompt can be reviewed.

## Open questions

- How later iterations proceed: whether only the student reruns with the new revision while the teacher trial is reused, and when the exercise stops (iteration limit, score threshold, or manual).
- Whether the teacher's evaluation is scored per test case, summarised across the suite, or both.

## Explicitly deferred

User accounts and multi-user authorization, alternative hosted inference providers, distributed workers, general-purpose automated LLM judging outside of refinement, statistical significance analysis, and managed remote deployment are outside the first release. The data model and service boundaries should avoid preventing these additions later.
