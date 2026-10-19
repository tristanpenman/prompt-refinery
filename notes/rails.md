# Rails

Prompt Refinery is a local-first Rails application for authoring prompts and test suites, running them against Ollama-compatible backends, and reviewing their responses. Rails owns the web interface, SQLite persistence, immutable trial history, background execution, and communication with Ollama.

## Current stack

- **Runtime:** Ruby 3.4.9 and Rails 8.1. The bundle currently resolves Rails 8.1.4; the Gemfile allows compatible Rails releases from 8.1.3 onward (`~> 8.1.3`). Rails configuration defaults are set to 8.1.
- **Web interface:** Server-rendered views with Turbo and Stimulus, import maps, and Propshaft. Model responses are rendered as Markdown with Commonmarker.
- **Persistence:** SQLite through Active Record. Active Job uses the database-backed Solid Queue adapter in development and production, with a separate Compose worker. Solid Cache and Solid Cable are bundled but are not currently configured as the cache and Action Cable adapters.
- **Model runtime:** Ollama's HTTP API, through one or more configured backends. The application lists installed models per backend and reports connection and generation errors. `OLLAMA_URL` sets the system backend's endpoint and defaults to the Compose `ollama` service.
- **Packaging:** Ruby, Rails, Bundler, the web process, and the job worker run through Docker Compose. The Compose stack also provides Ollama, while `OLLAMA_URL` can point to another Ollama server. The host Ruby environment is not supported as a project runtime.
- **Authentication:** An optional encrypted token protects the application through an HTTP-only session cookie. Generate its configured value with `bin/rails prompt_refinery:encrypt_token` inside Compose.

Use `scripts/compose.sh` to build or refresh the stack. Run Rails, Bundler, and test commands in the `app` service; use `docker compose exec app ...` when it is already running and `docker compose run --rm app ...` otherwise.

## Current data model

- `Backend` is an inference server Prompt Refinery can use. The system backend is created from `OLLAMA_URL`, cannot be deleted or demoted, and can be disabled. Other Ollama-compatible backends are managed under Settings.
- `LanguageModel` records a model name discovered on a backend. `LanguageModelFamily` groups models; a family is derived from the model name (`gemma3:4b` → `gemma3`) unless one is chosen in Settings, and empty families are removed.
- `Prompt` is the mutable authoring identity for a prompt's name and template. Prompts can be archived instead of deleted; archived prompts are read-only, cannot start new trials, and remain available to historical trials.
- `PromptRevision` is an immutable, numbered snapshot of a prompt's name and template.
- `TestSuite` is the mutable authoring identity for a named set of variables and the test cases that supply them. Suites are archived rather than deleted, with the same read-only rules as prompts.
- `TestCase` supplies a text value for every variable in its suite. Removing a test case soft-deletes it so revision references remain valid. Changing a suite's variables drops values for removed variables and adds blank values for new ones.
- `TestSuiteRevision`, `TestCaseRevision`, and `TestSuiteRevisionCase` are immutable snapshots of a suite's name and variables, each case's values, and the suite's ordered case membership.
- `Trial` records the selected backend (with a snapshot of its name and URL) and model, and references a prompt revision and a test suite revision.
- `Response` references a trial and one test suite revision case, and stores the exact rendered prompt, generated content or error, and execution status.

## Versioning and trial execution

Revisions are captured when a trial is created, not after every edit. SHA-256 content digests allow unchanged prompt, test suite, and test case snapshots to reuse existing revisions; changed content receives the next per-record version number. Revision models reject updates, and database uniqueness and foreign-key constraints protect the revision graph. See [versioning.md](versioning.md) for the design.

Prompt templates use `{{name}}` placeholders. `PromptTemplate` lists the variables a template uses and renders it with a test case's values.

Trial creation is transactional:

1. Capture or reuse the prompt's current immutable revision.
2. Capture or reuse the test suite's current immutable revision, including a revision for each active test case.
3. Create a pending trial, validating that the prompt and suite are active, the suite has at least one test case, every variable the prompt uses is provided by the suite, and the backend is enabled.
4. Create one pending response per test case in position order, storing the template rendered with that case's values in `rendered_prompt`.
5. Commit, then enqueue `TrialExecutionJob` through Solid Queue.

The worker reads the stored `rendered_prompt`, so later prompt or test suite edits cannot change a queued or completed run. It sends one generation request per response in test case order, records errors per response, and marks the trial completed or failed. Trial and comparison pages read the historical revision data rather than mutable authoring fields.

## Implemented workflows

- Create, edit, archive, and unarchive prompts, and inspect their revision history.
- Create, edit, archive, and unarchive test suites; add, edit, and remove their test cases; and inspect suite revision history.
- Manage backends, test their connections, and assign model families under Settings.
- Discover models from every enabled backend, and run a prompt against a test suite as a queued trial.
- Review each test case's variables, rendered prompt, and output or failure for a trial.
- Compare two trials' responses for the test cases they share, including trials of different prompt revisions.
- Use the playground and single-prompt evaluation screens for untracked experimentation.

## Remaining planned scope

Generation settings and runtime/model digests, timing metrics, scoring, reviewer notes, filtering, JSON/CSV export, CSV import of test cases, cancellation, and retry controls remain future work. See [PLAN.md](../PLAN.md).

Tests currently cover models, controllers, prompt templates, the inference client boundary, trial execution, authentication, and the health endpoint with test doubles where appropriate. A real-Ollama end-to-end smoke test and explicit CPU/GPU environment coverage remain useful follow-up work.
