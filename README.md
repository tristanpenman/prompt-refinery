# Prompt Refinery

Prompt Refinery is a local-first tool for evaluating collections of related prompts against language models.

It is intended to make prompt experimentation repeatable and easy to review. A prompt collection can contain both fixed prompts and templates whose variables are filled with user-provided inputs. Prompt Refinery runs those prompts as a tracked trial, preserves the generated outputs, and provides an interface for reviewing, comparing, and scoring the results.

## Goals

- Organize related prompts into reusable collections.
- Support static prompts and prompts with interpolated input variables.
- Create and monitor trial runs across prompts and input cases.
- Preserve prompts, inputs, model settings, outputs, errors, and timing information.
- Review, compare, score, and annotate generated responses.
- Export trial results for further analysis.
- Keep inference and evaluation data on the local machine.

## Model runtime

Prompt Refinery uses [Ollama](https://ollama.com/) to run models locally. Ollama will use a supported GPU when one is available and otherwise fall back to CPU execution.

## Application

The application is planned as a Ruby on Rails web app using Hotwire for interactive workflows, SQLite for persistence, and Active Job for trial execution.

Development and installation instructions will be added when the initial application scaffold is in place. See [PLAN.md](PLAN.md) for the proposed scope, architecture, and delivery milestones.
