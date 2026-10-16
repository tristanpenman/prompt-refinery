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

## Local development

Prompt Refinery is a Rails 8.1 application using Hotwire, SQLite, and Solid Queue. Ruby and Rails run in Docker; Ollama runs locally and is reached from the app at `http://host.docker.internal:11434` by default.

Prerequisites:

- Docker with Compose v2
- [Ollama](https://ollama.com/) running on the host

Start the application:

```sh
scripts/compose.sh
```

Then open http://localhost:3000. Override the Ollama endpoint with `OLLAMA_URL` when needed.

### Authentication

Generate an encrypted authentication token interactively:

```sh
docker compose run --rm app bin/rails prompt_refinery:encrypt_token
```

Add the generated value to the local `.env` file and restart Prompt Refinery:

```dotenv
RAILS_AUTH_TOKEN=<encrypted value>
```

Enter the original plaintext token on the login page. Prompt Refinery stores it in an encrypted, HTTP-only session cookie. You can also use a one-time-style login URL such as `https://prompt_refinery.example.test/?token=<plaintext token>`; Prompt Refinery removes the token from the URL after setting the cookie.

Common commands:

```sh
docker compose run --rm app bin/rails test
docker compose run --rm app bin/rails console
docker compose logs -f app
docker compose down
```

See [PLAN.md](PLAN.md) for the proposed scope, architecture, and delivery milestones.

## License

Prompt Refinery is licensed under the [MIT License](LICENSE).
