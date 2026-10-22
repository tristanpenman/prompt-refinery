# Models for a 12 GB GPU budget

These are the largest models that fit within 12 GB of GPU memory when served by Ollama. About 2 GB of that budget goes to the KV cache and runtime overhead at a 4–8k context, leaving roughly 10 GB for weights. Sizes are approximate download sizes for the default Ollama library tags (mostly Q4_K_M) and should be confirmed with `ollama ps` after loading, which also shows whether any layers spilled to the CPU. Ollama has no hard VRAM limit; on a 16 GB card, setting `OLLAMA_GPU_OVERHEAD=4294967296` (4 GB) on the `ollama` service reserves the remainder so models are planned against about 12 GB.

| Model               | Approx. size | Notes                                                                |
| ---                 | ---          | ---                                                                  |
| `qwen3:14b`         | 9.3 GB       | Strong general model with a thinking mode                            |
| `phi4:14b`          | 9.1 GB       | Good at reasoning and instruction following                          |
| `deepseek-r1:14b`   | 9.0 GB       | Reasoning distill; slow because of long thinking output              |
| `qwen2.5-coder:14b` | 9.0 GB       | Code-focused                                                         |
| `gemma3:12b`        | 8.1 GB       | Includes vision; the QAT variant `gemma3:12b-it-qat` is about 8.9 GB |
| `mistral-nemo:12b`  | 7.1 GB       | 128k context window, though long contexts use a lot of VRAM          |
