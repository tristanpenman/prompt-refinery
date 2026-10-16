# Rails

Prompt Refinery is a local-first Rails application for authoring prompt collections, running them against Ollama, and reviewing their responses. Rails owns the web interface, SQLite persistence, immutable trial history, background execution, and communication with Ollama.

## Current stack

- **Runtime:** Ruby 3.4.9 and Rails 8.1. The bundle currently resolves Rails 8.1.4; the Gemfile allows compatible Rails releases from 8.1.3 onward (`~> 8.1.3`). Rails configuration defaults are set to 8.1.
- **Web interface:** Server-rendered views with Turbo and Stimulus, import maps, and Propshaft. Model responses are rendered as Markdown with Commonmarker.
- **Persistence:** SQLite through Active Record. Active Job uses the database-backed Solid Queue adapter in development and production, with a separate Compose worker. Solid Cache and Solid Cable are bundled but are not currently configured as the cache and Action Cable adapters.
- **Model runtime:** Ollama's HTTP API. The application lists installed models and reports connection and generation errors. `OLLAMA_URL` selects the endpoint and defaults to the Compose `ollama` service.
- **Packaging:** Ruby, Rails, Bundler, the web process, and the job worker run through Docker Compose. The Compose stack also provides Ollama, while `OLLAMA_URL` can point to another Ollama server. The host Ruby environment is not supported as a project runtime.
- **Authentication:** An optional encrypted token protects the application through an HTTP-only session cookie. Generate its configured value with `bin/rails prompt_refinery:encrypt_token` inside Compose.

Use `scripts/compose.sh` to build or refresh the stack. Run Rails, Bundler, and test commands in the `app` service; use `docker compose exec app ...` when it is already running and `docker compose run --rm app ...` otherwise.

## Current data model

- `Collection` is the mutable authoring identity. It has ordered prompts and can be archived instead of deleted. Archived collections and prompts are read-only, cannot start new trials, and remain available to historical trials.
- `Prompt` is a mutable prompt identity within a collection. Removing a prompt soft-deletes it so revision and response references remain valid.
- `CollectionRevision` is an immutable, numbered snapshot of a collection's name, prompt membership, and ordering.
- `PromptRevision` is an immutable, numbered snapshot of a prompt's name and template.
- `CollectionRevisionPrompt` joins a collection revision to its ordered prompt revisions.
- `Trial` records the selected model and references both the stable collection and the authoritative collection revision.
- `Response` references a trial and revision member, and stores the exact rendered prompt, generated content or error, and execution status.

## Versioning and trial execution

Revisions are captured when a trial is created, not after every edit. SHA-256 content digests allow unchanged collection and prompt snapshots to reuse existing revisions; changed content receives the next per-record version number. Revision models reject updates, and database uniqueness and foreign-key constraints protect the revision graph.

Trial creation is transactional:

1. Capture or reuse the collection's current immutable revision and its prompt revisions.
2. Create a pending trial for that collection revision.
3. Create one pending response per revision member in prompt order, copying the prompt text into `rendered_prompt`.
4. Commit, then enqueue `TrialExecutionJob` through Solid Queue.

The worker reads the stored `rendered_prompt`, so later collection or prompt edits cannot change a queued or completed run. It processes responses in revision order, records Ollama errors per response, and marks the trial completed or failed. The collection history UI exposes numbered revisions and their prompt snapshots; trial and comparison pages read the historical revision data rather than mutable authoring fields.

The direct `Trial -> Collection` and `Response -> Prompt` relationships remain for identity and convenient querying, but revision references and response snapshots are authoritative for historical content.

## Implemented workflows

- Create, edit, archive, and unarchive collections.
- Create, edit, reorder, and soft-delete prompts.
- Inspect immutable collection and prompt revision history.
- Discover models from Ollama and run a collection as a queued trial.
- Review per-prompt outputs and failures and compare a trial's responses.
- Use standalone prompt and multi-prompt evaluation screens for untracked experimentation.
- Retain completed trials when their source collection is archived.

## Remaining planned scope

The current schema does not yet include input cases or interpolation of template variables during trial creation; trial prompts are presently copied verbatim. Generation settings and runtime/model digests, timing metrics, scoring, reviewer notes, filtering, JSON/CSV export, cancellation, and retry controls also remain future work.

Tests currently cover models, controllers, the Ollama client boundary, trial execution, authentication, and the health endpoint with test doubles where appropriate. A real-Ollama end-to-end smoke test and explicit CPU/GPU environment coverage remain useful follow-up work.
