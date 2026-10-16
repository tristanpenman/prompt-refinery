# Multiple inference backends

Prompt Refinery currently has one process-wide inference backend. `Ollama::Client` reads `OLLAMA_URL`, every controller constructs the client directly, model choices contain only an Ollama model name, and `TrialExecutionJob` constructs a fresh client without any persisted endpoint information. Supporting multiple Ollama-compatible servers therefore requires more than accepting an array of URLs: the selected backend must become part of model identity and part of a trial's immutable execution input.

The local Compose Ollama service should remain the required default. Additional endpoints would be user-configured and could include another Ollama server or an Ollama-compatible implementation such as [rkllama](https://github.com/NotPunchnox/rkllama) on a Rockchip development board. rkllama advertises the two endpoints Prompt Refinery currently needs, `GET /api/tags` and `POST /api/generate`, so the existing protocol is a useful starting point. Compatibility should still be treated as a capability to verify rather than an assumption that every Ollama endpoint and response field behaves identically.

## Proposed model

Add a `Backend` record with approximately these fields:

| Field                      | Purpose                                                                                                      |
| ---                        | ---                                                                                                          |
| `name`                     | User-facing, unique label such as `Local Ollama` or `RK3588 board`                                           |
| `base_url`                 | Normalized origin and optional path prefix, without a trailing slash                                         |
| `adapter`                  | Initially `ollama`; allows a distinct adapter later without encoding implementation type in application code |
| `enabled`                  | Removes an endpoint from new work without invalidating history                                               |
| `system`                   | Marks the non-removable default backend                                                                      |
| `created_at`, `updated_at` | Configuration audit context                                                                                  |

The default record would be created automatically from `OLLAMA_URL` (still defaulting to `http://ollama:11434`) and marked `system`. It should always exist, be enabled, and not be deletable. Environment configuration remains the authority for its URL so deployments can continue to select the Compose service or an external Ollama without first visiting the UI. A boot-time upsert or idempotent seed is preferable to silently creating it during a request.

Alternative endpoints can be managed in a Backends settings screen. They should normally be archived/disabled rather than deleted because trials will refer to them. The first version does not need routing, load balancing, or fallback: a user explicitly chooses one backend and failures stay attributed to it. Automatic fallback would undermine evaluation reproducibility and could accidentally run a model with the same name but different weights.

Add `backend_id` to `trials`, make it required, and associate existing trials with the default backend in the migration. `Trial.create_for!` should require a backend along with the model. The background job must resolve the client from `trial.backend`, not from current UI state or a global default.

For useful historical records, a trial should also snapshot the backend display name and normalized URL used when it was queued (and eventually runtime version, model digest, generation options, and returned timing data). The foreign key identifies the configured backend; snapshots explain an old result after that backend is renamed or repointed. Credentials must never be copied into a trial snapshot. Repointing an existing backend is potentially misleading, so either prevent URL changes after it has trials or model endpoint changes as revisions. The simpler initial policy is to require creating a new backend when the URL changes.

Model identity in forms and links becomes `(backend_id, model_name)`, not just `model_name`. Do not concatenate these into a string that later has to be parsed. Prompt and evaluation URLs should carry a backend identifier separately, and trial tables, result pages, and comparison screens should show the backend label beside the model.

## Application boundary

Controllers and jobs should stop referring directly to `Ollama::Client`. Introduce a small factory or registry, for example `Inference::Client.for(backend)`, which validates the adapter and returns an Ollama-compatible client initialized with that backend's URL. The application-facing interface can remain small:

```ruby
client.models
client.generate(model:, prompt:)
client.version # optional capability/diagnostic
```

This keeps endpoint selection in one place and preserves a test seam. It also avoids spreading conditionals for rkllama throughout controllers. rkllama should initially use the `ollama` adapter; introduce a dedicated adapter only when an observed incompatibility requires request or response translation.

`Ollama::Client` already accepts `base_url:`, but it needs a few hardening changes for user-supplied endpoints:

- Validate the URL when saving a backend. Permit only `http` and `https`, require a host, reject userinfo and fragments, normalize trailing slashes, and define whether path prefixes are supported.
- Preserve query/path behavior deliberately instead of relying on surprising `URI.join` replacement rules.
- Include the backend label in connection errors so failures remain understandable when several endpoints are displayed.
- Make timeouts backend-configurable only if real hardware demonstrates a need. The existing 300-second generation timeout may be too short for a small edge model on first load, but arbitrary user-controlled timeout values add complexity.
- Optionally call `/api/version` as a diagnostic, while treating it as nonessential to model listing and generation.

The dashboard and Models page need a presentation decision. The clearest first implementation is a backend selector, defaulting to Local Ollama, followed by the models returned by that one endpoint. The trial form should select a backend first and then populate only that backend's models. Grouping all models from all endpoints is possible, but it creates slower pages, partial-failure handling, duplicate names, and fan-out requests on every load. If model lists are fetched concurrently or cached later, errors and cache entries must remain per backend.

Standalone prompt and evaluation flows also need to preserve `backend_id` between their GET and POST requests. The server must verify that the submitted model is available on the selected, enabled backend; at minimum it must never accept a client-supplied URL. Only stored backend IDs should cross the form boundary.

## rkllama on an edge board

rkllama's current documentation lists Ollama-compatible `/api/generate`, `/api/tags`, and `/api/version` endpoints, among others. Prompt Refinery sends non-streaming generation requests (`stream: false`) and reads the `response` field, which is the smallest compatibility surface to prove. Before calling the integration supported, add a smoke/contract test against the deployed board that checks:

1. `GET /api/tags` returns a `models` array with usable `name` values.
2. `POST /api/generate` accepts `{ model, prompt, stream: false }` and returns a JSON `response` string.
3. Missing-model, busy-device, timeout, and malformed-response failures produce useful errors.
4. Model names shown by `/api/tags` can be sent back unchanged to `/api/generate`.
5. Duration and model metadata are interpreted only after their format and units have been verified; they should not be assumed to be identical merely because generation is compatible.

rkllama commonly listens on port `8080`, so a LAN configuration might be `http://edge-board.local:8080`. Because Prompt Refinery runs inside Docker, `localhost` means the Rails container, not the host or the board. A service on the Docker host can use the existing `host.docker.internal` mapping; a board should use an address or DNS name reachable from both the `app` and `jobs` containers. rkllama must listen on an externally reachable interface, and the board firewall must allow the Docker host to connect.

There is no need to add rkllama to Prompt Refinery's Compose stack: it depends on the board's Rockchip NPU and should be managed on that device. Prompt Refinery only stores its HTTP endpoint.

## Security and operations

An editable backend URL is a server-side request forgery boundary. Authentication protects the settings UI but does not make arbitrary destinations safe. At minimum:

- Resolve and validate destinations at request time, not only when saving; DNS can change.
- Default to blocking loopback, link-local, cloud metadata, and unrelated private-network targets. A local-first deployment may need private LAN addresses for the edge board, so use an explicit allowlist of hosts or CIDRs rather than declaring all private addresses safe.
- Do not follow redirects to an unvalidated host.
- Limit response sizes and retain connection/read timeouts.
- Never expose raw exception details or credentials in the UI or logs.

If an endpoint later requires authentication, store a credential reference or encrypted secret separately from `base_url` and add headers in the adapter. URLs containing credentials should be rejected. The local and rkllama cases should not require credentials on a trusted LAN, but exposing either API beyond that LAN without TLS and authentication would allow other users to consume compute and inspect model inventory.

Health should be shown per backend as observed state (last successful check, error, and timestamp), not as a prerequisite that prevents saving a temporarily offline board. The Rails `/up` endpoint should continue to report application health; an optional readiness or diagnostics page can report inference backend availability without making Rails itself unhealthy when an alternative endpoint is down. The always-present local backend may still be unavailable while Ollama starts, which should remain a recoverable UI error.

## Suggested implementation sequence

1. Add `Backend`, seed/upsert the system default, add the settings UI, and cover URL normalization, immutability, enablement, and deletion rules.
2. Add and backfill `trials.backend_id` plus backend snapshot fields. Change trial creation and execution so the selected endpoint survives the queue boundary.
3. Add the client factory and pass explicit backend URLs everywhere. Keep `Ollama::Client` as the first adapter and update controller/job test doubles at the factory boundary.
4. Add backend selection to model discovery, standalone prompts, evaluations, trials, result pages, and comparisons. Ensure links and form submissions carry IDs rather than URLs.
5. Add partial-failure tests and an Ollama-compatible contract test. Run the same contract manually or in an opt-in integration suite against rkllama on the board.
6. Only after measuring real use, consider per-backend caching, capability discovery, custom timeouts, credentials, concurrent fan-out, or routing policies.

The minimum valuable slice is explicit backend selection with trial persistence and the existing Ollama protocol. That is enough to use rkllama without prematurely creating a general multi-provider abstraction, while leaving a clean boundary for compatibility fixes discovered on the hardware.
