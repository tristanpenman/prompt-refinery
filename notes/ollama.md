# Ollama inference parameters

Prompt Refinery can override Ollama's model defaults for each trial by passing an `options` object to [`POST /api/generate`](https://docs.ollama.com/api/generate) or [`POST /api/chat`](https://docs.ollama.com/api/chat). Parameters omitted from the request retain the model or server default. The exact submitted options, model name and digest, prompt, and runtime version should be stored with the trial because defaults and supported options can change.

For example:

```json
{
  "model": "qwen3:1.7b",
  "prompt": "Explain the result.",
  "stream": false,
  "options": {
    "seed": 42,
    "temperature": 0.2,
    "top_k": 20,
    "top_p": 0.9,
    "num_ctx": 2048,
    "num_predict": 128
  },
  "keep_alive": "10m"
}
```

## Useful trial controls

| Parameter | What it changes | Trial considerations |
| --- | --- | --- |
| `seed` | Random-number seed used while sampling. | Fix it when comparing prompts or runtimes. A fixed seed improves repeatability within one runtime, but does not guarantee identical output across runtime versions, quantizations, or hardware backends. |
| `temperature` | Flattens or sharpens the next-token distribution. Lower values are more conservative; higher values are more varied. | This is usually the first creativity knob to expose. Include a low-temperature baseline, but do not describe it as fully deterministic. |
| `top_k`, `top_p`, `min_p` | Restrict the candidate tokens before sampling. | Change one family of sampling controls at a time. `top_k = 1` is a useful greedy-style baseline and is widely portable. |
| `repeat_penalty`, `repeat_last_n` | Penalize recently used tokens and select how much history is inspected. | Useful for repetitive small models. Aggressive values can damage code, quoted text, and deliberate repetition. `repeat_last_n` is less consistently exposed by embedded runtimes. |
| `presence_penalty`, `frequency_penalty` | Penalize tokens already present, either once or in proportion to frequency. | Record explicit zero values when testing portability; some runtimes do not implement these penalties in exactly the same way. |
| `num_predict` | Maximum generated tokens. | A direct latency and energy bound. It should nearly always be finite for unattended trials. Early EOS or a stop sequence can still end generation sooner. |
| `stop` | One or more byte/text sequences that end generation. | Store these with the prompt template. Different chat templates and tokenization can make apparently equivalent stop conditions behave differently. |
| `num_ctx` | Context-window capacity, in tokens. | Larger values permit longer prompts/history but increase KV-cache memory and can change allocation or model-load behavior. Do not set it above the model/runtime's supported context merely because the API accepts an integer. |
| `num_batch` | Prompt-processing batch size. | Larger batches may improve prefill throughput at the cost of a sometimes substantial memory spike. It is a performance setting, not the number of trial items to execute concurrently. |
| `num_thread` | CPU worker threads. | Relevant to CPU inference and tokenization; more threads can increase power use or contention without improving throughput on a small device. |
| `num_gpu`, `main_gpu` | Layer offload and GPU selection in Ollama's underlying runner. | Hardware-specific and not portable to an NPU runtime. Prefer automatic placement unless the trial is explicitly measuring deployment configuration. |
| `use_mmap` | Whether model weights may be memory-mapped. | Can reduce load pressure or allow the OS to page weights, but storage speed and memory pressure can dominate on embedded systems. Treat it as an environment parameter rather than a model-quality parameter. |
| `draft_num_predict` | Number of speculative draft tokens attempted per step when the model/runtime supports drafting. | Can trade extra work and memory for speed. Results and timing are runtime-dependent; set it to `0` for a simple cross-runtime baseline. |
| `keep_alive` | How long Ollama retains the loaded model after the request. This is a top-level request field, not an `options` entry. | It changes cold-start frequency and resident memory, not sampling. Use `0` to unload after a trial or a longer duration when measuring warm inference. |

The generation controls documented for Ollama Modelfiles are listed in the [official parameter reference](https://docs.ollama.com/modelfile#valid-parameters-and-values). Ollama also returns `load_duration`, `prompt_eval_count`, `prompt_eval_duration`, `eval_count`, and `eval_duration`; retain these so load time, time to process the prompt, and token-generation speed can be compared separately.

## Embedded runtimes such as RKLLama

The most important embedded controls are **`num_ctx`, `num_predict`, and model quantization**. Context capacity determines KV-cache pressure, output length bounds worst-case run time, and the model artifact's size/quantization often determines whether the model fits at all. Quantization is normally chosen when preparing or selecting the model, rather than as an Ollama request option, so record the exact artifact and quantization alongside every result.

Keep the portable trial preset small:

- `temperature`, `top_k`, `top_p`, `repeat_penalty`, and the output-token limit have close equivalents in Rockchip's [RKLLM runtime API](https://github.com/airockchip/rknn-llm/blob/main/rkllm-runtime/Linux/librkllm_api/include/rkllm.h). `min_p` is available in RKLLama's llama.cpp-based server but is not exposed by Rockchip's native API, so omit it from a native-RKLLM portability preset.
- Ollama `num_ctx` corresponds conceptually to RKLLM `max_context_len`, and `num_predict` to `max_new_tokens`. Validate both against the converted model; an embedded model may have a fixed or lower context ceiling.
- Do not translate Ollama `num_gpu`, `main_gpu`, or `num_thread` literally to an NPU. NPU core/domain selection, CPU affinity, and weight placement are deployment settings with different meanings.
- RKLLama's llama.cpp-based server accepts settings such as `batch-size`, `ubatch-size`, KV-cache types, `cache-ram`, `mmap`, and sampling controls through its [`config.ini`](https://github.com/NotPunchnox/rkllama#customize-configini). Those settings can materially change memory use and prefill speed and may require a server/model reload, so record them as runtime configuration rather than per-response generation settings.
- Keep trial concurrency separate from inference batching. Several simultaneous requests can multiply model state and KV-cache use; begin with one in-flight generation on memory-constrained hardware.
- Measure cold and warm runs separately. Model loading and storage I/O can dwarf generation time on an embedded board, while retaining a model improves latency at the cost of keeping scarce RAM occupied.
- Capture device, runtime/library and driver versions, model format and quantization, context and output lengths, prompt and generated token counts, time to first token or prefill time, decode tokens/second, peak memory, and whether the run was cold. Rockchip's published [benchmarks](https://github.com/airockchip/rknn-llm/blob/main/benchmark.md) separate sequence length, new-token count, time to first token, tokens/second, and memory for the same reason.

A fair cross-runtime trial should first use the common sampling subset with speculative decoding disabled, one request at a time, a fixed finite context/output budget, and the same fully rendered prompt. Hardware tuning can then be a separate trial dimension rather than an accidental source of output or timing differences.
