# Plan

The goal of this project is to build a small local-first application for prompt engineering against models served by Ollama. Users iterate on a single prompt, evaluate each revision against a suite of test cases, review and score the generated responses, and use a stronger teacher model to refine the prompt for a weaker student model.

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

## Prompts

- ~~Create, edit, and delete collections, with deletion protected after use in a trial.~~
- ~~Add, edit, order, and delete prompts within a collection.~~
- ~~Store plain prompts and template text.~~
- ~~Track revisions of prompts and collections.~~
- Make the prompt the primary unit of evaluation. Prompts remain revision managed, and a trial refers to a prompt revision rather than a collection revision.
- Keep collections as an organisational grouping only; they no longer define what a trial runs.
- Duplicate prompts.

## Templating

- Render templates with named variables such as `{{topic}}`.
- Parse the variables a template uses and validate them against the selected test suite before a trial is created.
- Preview the fully rendered prompt for a chosen test case before execution.

## Test suites

- Create, edit, and archive test suites, managed centrally and independently of prompts.
- Store test cases within a suite, each providing a value for every variable in the suite.
- Import test cases from a CSV upload: the header row names the variables, and each subsequent row becomes a test case.
- Track revisions of test suites and test cases so a trial records exactly which cases it ran, and with which values, even after the suite is edited.
- Protect suites from deletion once they have been used in a trial.

## Trial runs

- ~~Select a collection and installed Ollama model.~~
- ~~Create persistent trial and response records before execution.~~
- ~~Queue work locally with configurable worker concurrency and execute prompts sequentially through Ollama's HTTP API.~~
- ~~Show pending, running, completed, and failed states with per-prompt responses and errors.~~
- ~~Preserve the collection, prompt relationship, model name, response or error, status, and trial timestamps.~~
- ~~Snapshot rendered prompts~~
- Select a prompt revision, test suite, model, and generation settings.
- Expand the trial into one immutable trial item per test case, each holding the rendered prompt and its response. Responses are keyed by trial and test case rather than by trial and prompt.
- Add cancellation and more detailed progress reporting.
- Allow failed items to be retried without rerunning successful items.

## Generation settings

- Choose generation parameters such as temperature, seed, and `num_ctx` when creating a trial.
- Record the parameters on the trial so reruns can be reproduced exactly.
- Capture Ollama's token counts and timings for each response.

## Review and scoring

- ~~Display the recorded prompt responses for a trial.~~
- ~~Compare responses from two trials side by side.~~
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
