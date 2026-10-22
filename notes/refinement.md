# Refinement

A refinement uses a stronger _teacher_ model to improve a prompt for a weaker _student_ model. The teacher runs the starting prompt once, and its outputs become the reference. On each iteration the student runs the current prompt, and the teacher compares the student's outputs with the reference and proposes a revised prompt. Every iteration is recorded, so you can review how the prompt changed.

The data model, the refinement pages, and running one iteration at a time are implemented. Stopping rules, **Stop**, and **Apply to original** are not yet. See also [versioning.md](versioning.md).

## How it works

1. **Start.** The user picks a prompt, a test suite, a student, and a teacher (each a backend and model). The refinement records the starting prompt revision, captures a test suite revision, and creates a _working prompt_ as a copy of the starting prompt.
2. **Reference trial.** The teacher runs the starting revision against the suite, once.
3. **Iteration _n_.** The student runs the working prompt's current revision against the suite. The teacher then _evaluates_ it: one fresh request containing the evaluator instructions, the current prompt, and each test case with its reference and student outputs. It returns a verdict per test case, a summary, and a proposed prompt.
4. **Next.** Unless a stopping rule applies, the proposed prompt is written to the working prompt and captured as a new revision for iteration _n_ + 1.

## Decisions

- **Only the student reruns.** The reference trial is reused by every iteration. This halves the cost per iteration and keeps the target fixed. The evaluator instructions tell the teacher to keep the task and output format unchanged.
- **Scoring.** Each test case gets a verdict of `match`, `partial`, or `miss`, with a short note. A failed student response counts as `miss`. The iteration's agreement is `(matches + 0.5 × partials) / test cases`. It's the teacher judging against its own reference, so treat it as a guide.
- **Stopping.** A refinement stops at the first of these:
  - the iteration limit (default 3, at most 10);
  - reaching the target agreement (default 1.0);
  - convergence (the teacher proposes the same prompt, or says it's done);
  - the user pressing **Stop** (checked between steps);
  - a failure.

  A stopped or failed refinement can be continued.
- **A working prompt, not the original.** Writing revisions to the user's prompt would overwrite their edits, or mark the prompt as having draft changes. Refinements write to their own copy instead. **Apply to original** copies a chosen revision back to the original prompt as a draft.
- **Pinned inputs.** All trials use the test suite revision captured at the start, so editing the suite mid-way doesn't change the comparison. This needs `Trial.create_from_revisions!`.
- **Instructions are stored text.** The evaluator instructions are copied onto each refinement from [`app/prompts/refinement_evaluator.md`](../app/prompts/refinement_evaluator.md), and can be edited on the form. They're rendered with `PromptTemplate`, using only these variables:
  - `{{current_prompt}}`
  - `{{variables}}`
  - `{{cases}}`
  - `{{history}}` (one line per earlier iteration)

  The default describes placeholders in words, because literal double braces would be read as a variable.
- **Structured output.** The evaluation asks for JSON, using Ollama's `format` option at temperature 0:

  ```json
  { "cases": [{ "case": 1, "verdict": "match", "notes": "..." }], "summary": "...", "changes": "...", "done": false, "prompt": "..." }
  ```

  A reply is rejected if it doesn't match the schema, has the wrong number of cases, or proposes a prompt that uses variables the suite doesn't have. A rejected reply is retried once, with the reason added to the request; a second rejection fails the iteration. This needs `format:` and `options:` on `Inference::Client#generate`.

## Data model

Ruby already has a core `Refinement` class, so the models are `PromptRefinement` (`prompt_refinements`) and `PromptRefinementIteration` (`prompt_refinement_iterations`). Associations use short names such as `prompt.refinement`, `iteration.refinement`, and `trial.reference_refinement`.

```
PromptRefinement ─┬─ starting PromptRevision (original prompt)
                  ├─ working Prompt ── PromptRevisions
                  ├─ TestSuiteRevision
                  ├─ reference Trial (teacher)
                  └─ PromptRefinementIterations ─┬─ PromptRevision (working prompt)
                                                 └─ student Trial
```

- **`PromptRefinement`** holds:
  - the inputs above, with copies of the student and teacher backends' names and URLs;
  - the instructions;
  - `max_iterations`, `target_agreement`, and `context_size`;
  - `status` (`pending`, `running`, `completed`, `stopped`, or `failed`);
  - `stop_reason`, `stop_requested_at`, and timestamps.

  The inputs can't change after creation, except `max_iterations`. On create it makes the same checks as `Trial`: an active prompt and suite, test cases that supply the prompt's variables, and enabled backends.
- **`PromptRefinementIteration`** holds:
  - `number`, the prompt revision, and the student trial;
  - `status` (`pending`, `running_trial`, `evaluating`, `completed`, or `failed`);
  - the exact evaluation request and raw reply;
  - `case_evaluations` (JSON keyed by test suite revision case id);
  - `agreement`, `summary`, `change_summary`, `proposed_template`, and `error`.

  A completed iteration can't be changed.
- **Deletion.** Prompts, revisions, backends, and trials that a refinement depends on can't be deleted.

## Execution

For now, **Run iteration** on the refinement page marks the refinement as running and enqueues a `RefinementJob`, which runs one whole iteration and returns the refinement to pending. A failure is recorded on the iteration, and failed iterations don't count towards the limit. Eventually a `RefinementJob` will perform one step and then enqueue the next. Trials run inline through `TrialExecutionJob.perform_now`, so they appear on the normal trial pages. Each step does nothing if the refinement has already finished, so a duplicate enqueue is harmless. **Stop** takes effect between steps. Tests use a fake client through the existing `client_factory` pattern.

- **Failures:**
  - If the reference trial fails, or a student trial fails entirely, the refinement fails.
  - If only some student responses fail, they count as `miss` and the evaluation goes ahead.
  - If an evaluation is rejected twice, the iteration fails, keeping the request and reply for diagnosis.
  - Continuing a failed refinement reruns only the failed step.
- **Context size.** The evaluation prompt can be longer than Ollama's default context window, and Ollama cuts long prompts without any error. To avoid this:
  - send `num_ctx`, from `context_size` (default 16k);
  - fail if the prompt's estimated size doesn't fit;
  - cut each output in `{{cases}}` to 2,000 characters.
- **Noise.** Until generation settings exist (see PLAN.md), agreement changes between iterations may be noise. Refinement trials should use temperature 0 and a fixed seed once that's possible.

## User interface

- **`/refinements`:**
  - a list showing the prompt, student → teacher, status, iterations run, and best agreement;
  - a **New refinement** form, which works like the trial form, with the instructions prefilled.
- **Refinement page:**
  - status and stop reason, and links to the starting revision and the reference trial;
  - **Stop** and **Continue**;
  - an agreement chart;
  - one card per iteration, with a diff of its prompt, its agreement, the teacher's summary, the verdict for each case, and **Apply to original**.

  The page updates live with Turbo Streams. The diff needs `diff-lcs`.
- **Trial and prompt revision pages** link back to their refinement.

## Implementation order

1. `Trial.create_from_revisions!`, and `format:`/`options:` on `Inference::Client#generate`.
2. Prompt duplication, shared with the "Duplicate prompts" item in PLAN.md.
3. ~~Models, migrations, and validations.~~
4. Building the evaluation prompt and validating the teacher's reply.
5. `RefinementJob`, with the stopping rules and failure handling.
6. The refinements list, form, and page, with Stop and Continue.
7. The diff, the agreement chart, Apply to original, and links back from trials and revisions.
8. Demo data.

## Open questions

- **Evaluator model.** Should the evaluator be allowed to be a different model from the teacher?
- **Best revision.** Is it the latest revision, or the one with the highest agreement, when results are noisy?
- **Large suites.** Should a suite too large for the context window fail, or be sampled?
- **Concurrency.** Can several refinements run at once on one backend?
