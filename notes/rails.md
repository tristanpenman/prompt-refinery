# Rails

This note documents how Rails will be responsible the web interface, as well as persistence, trial orchestration, and communication with Ollama. All data will be stored locally using SQLite and inference will be performed locally using Ollama.

- **Application:** Ruby on Rails with server-rendered views, Hotwire (Turbo and Stimulus) for interactive prompt editing, live run progress, and keyboard-friendly review.
- **Background work:** Active Job for trial execution. Use the Rails database-backed queue adapter for the initial single-user MVP so no separate queue service is required.
- **Storage:** SQLite with Active Record migrations; serialize structured fields such as inputs and model parameters as JSON.
- **Model runtime:** Ollama HTTP API. Detect availability at startup, list installed models, and report actionable connection errors.
- **Hardware:** Do not hard-code a device choice. Ollama automatically uses supported GPU acceleration when available and falls back to CPU. Surface runtime/model information in diagnostics so users can confirm the active environment.
- **Packaging:** Docker Compose for the application and documented support for either a host Ollama instance or an Ollama service. Also support direct local development without Docker.

Core entities:

- `Collection`: name, description, timestamps.
- `Prompt`: collection, name, template text, order.
- `InputCase`: collection, label, variable values.
- `Trial`: collection snapshot, model, generation settings, status, timestamps.
- `TrialItem`: trial, prompt snapshot, input snapshot, rendered prompt, response, status, timing, error.
- `Review`: trial item, score, decision, notes, timestamp.

## Delivery milestones

1. **Foundation** — Scaffold the Rails application, add SQLite migrations, health checks, Ollama connectivity, and development instructions.
2. **Authoring** — Implement collection, prompt, template-variable, and input-case management with rendering validation and preview.
3. **Execution** — Add trial creation, immutable snapshots, queued Ollama execution, progress reporting, cancellation, and retry handling.
4. **Review** — Build the output review workflow, scoring and notes, comparisons, filtering, and JSON/CSV export.
5. **Hardening** — Add automated tests, useful empty/error states, recovery after application restart, documentation, and a packaged local deployment.

## Testing strategy

- Unit-test template parsing/rendering, trial state transitions, scoring validation, and export formatting.
- Integration-test persistence and the Ollama client with a fake HTTP server so CI does not require a model.
- Add one opt-in end-to-end smoke test against a locally installed small Ollama model.
- Exercise CPU-only, GPU-enabled, unavailable-Ollama, interrupted-run, and malformed-template paths manually before the MVP release.

## MVP acceptance criteria

- A user can create a prompt collection containing both static and templated prompts.
- Missing or unexpected template inputs are identified before a run starts.
- A user can select an installed Ollama model and run all prompt/input combinations locally.
- Run progress and per-item failures remain visible, and completed results survive a restart.
- Every result records enough configuration and source data to understand how it was produced.
- A user can score, annotate, compare, filter, and export results.
- The application works without a GPU and benefits from GPU acceleration through Ollama when supported.
