# Plan

The goal of this project is to build a small local-first application for evaluating related sets of prompts against models served by Ollama. Users can define static or templated prompts, supply input values, run and monitor a trial, then review and score each generated response.

## Prerequisites

- ~~Rails project scaffolding.~~
- ~~Docker container for running Ollama on GPU or CPU.~~
- ~~Inspect installed models via the Rails frontend.~~
- ~~Minimal Jupyter-style token authentication.~~
- ~~Submit work to Ollama from the Rails frontend and monitor it through completion.~~

## Application shell

- ~~Provide a dashboard with recent models, collections, and trials.~~
- ~~Provide dedicated pages for installed models, prompt collections, and trials.~~
- ~~Run durable background jobs with Solid Queue in Docker Compose.~~

## Prompt collections

- ~~Create, edit, and delete collections, with deletion protected after use in a trial.~~
- ~~Add, edit, order, and delete prompts within a collection.~~
- ~~Store plain prompts and template text.~~
- Duplicate collections and track versions.
- Render templates with named variables such as `{{topic}}`.
- Validate templates and preview the fully rendered prompt before execution.
- Save reusable input rows so one collection can be evaluated against multiple cases.

## Trial runs

- ~~Select a collection and installed Ollama model.~~
- ~~Create persistent trial and response records before execution.~~
- ~~Queue work locally with configurable worker concurrency and execute prompts sequentially through Ollama's HTTP API.~~
- ~~Show pending, running, completed, and failed states with per-prompt responses and errors.~~
- ~~Preserve the collection, prompt relationship, model name, response or error, status, and trial timestamps.~~
- Select input cases and generation settings.
- Expand each prompt/input combination into an immutable trial item.
- Add cancellation and more detailed progress reporting.
- Snapshot rendered prompts and preserve model parameters and detailed timings for reproducibility.
- Allow failed items to be retried without rerunning successful items.

## Review and scoring

- ~~Display the recorded prompt responses for a trial.~~
- Review outputs one at a time or in a filterable table.
- Record a numeric score, optional pass/fail decision, and reviewer notes.
- Compare outputs from prompts and models side by side where they share the same input case.
- Export trial data and reviews as JSON and CSV.

## Explicitly deferred

User accounts and multi-user authorization, alternative hosted inference providers, distributed workers, automated LLM judging, statistical significance analysis, and managed remote deployment are outside the first release. The data model and service boundaries should avoid preventing these additions later.
