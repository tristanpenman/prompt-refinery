# Plan

The goal of this project is to build a small local-first application for evaluating related sets of prompts against models served by Ollama. Users can define static or templated prompts, supply input values, run and monitor a trial, then review and score each generated response.

## Prerequisites

- ~~Rails project scaffolding.~~
- ~~Docker container for running Ollama on GPU or CPU.~~
- ~~Inspect installed models via the Rails frontend.~~
- ~~Minimal Jupyter-style token authentication.~~
- Submit a job to Ollama from the Rails frontend and monitor its progress through to completion.

## Prompt collections

- Create, edit, duplicate, and delete collections.
- Add ordered prompts to a collection.
- Support plain prompts and templates with named variables such as `{{topic}}`.
- Validate templates and preview the fully rendered prompt before execution.
- Save reusable input rows so one collection can be evaluated against multiple cases.

## Trial runs

- Select a collection, input cases, an installed Ollama model, and generation settings.
- Expand each prompt/input combination into an immutable trial item.
- Queue work locally with configurable concurrency and execute it through Ollama's HTTP API.
- Show queued, running, completed, failed, and cancelled states, including progress and errors.
- Preserve the rendered prompt, model name, model parameters, response, timings, and run timestamp for reproducibility.
- Allow failed items to be retried without rerunning successful items.

## Review and scoring

- Review outputs one at a time or in a filterable table.
- Record a numeric score, optional pass/fail decision, and reviewer notes.
- Compare outputs from prompts and models side by side where they share the same input case.
- Export trial data and reviews as JSON and CSV.

## Explicitly deferred

Authentication and user management, alternative hosted inference providers, distributed workers, automated LLM judging, statistical significance analysis, and remote deployment are outside the first release. The data model and service boundaries should avoid preventing these additions later.
