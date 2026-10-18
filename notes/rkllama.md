# RKLLama on a Khadas Edge 2

This guide sets up [RKLLama](https://github.com/NotPunchnox/rkllama) on a Khadas Edge 2 running Ubuntu 24.04.

It documents a working installation using RKLLama 0.0.76, RKLLM Runtime 1.3.0, and the Khadas Ubuntu NPU driver 0.9.8. After installation, it downloads and serves Gemma 3 4B.

The example board has 8 GB of RAM. The quantized model is 5.62 GB and fits, but leaves little spare memory while loaded. This means that it will struggle with more than one inference request at a time.

## 1. Connect and check the board

SSH into the Edge 2 and confirm that it is running the expected architecture and OS:

```sh
ssh khadas@<edge-2-address>
uname -m
. /etc/os-release && echo "$PRETTY_NAME"
free -h
df -h /
```

The architecture must be `aarch64`. Check that the Rockchip NPU driver is loaded:

```sh
sudo dmesg | grep -i rknpu
find /sys -maxdepth 5 -iname '*rknpu*' 2>/dev/null
```

The tested Khadas image reported:

```text
RKNPU ... Initialized rknpu 0.9.8
```

The NPU may be exposed as a DRM render device rather than `/dev/rknpu`, so the absence of `/dev/rknpu*` alone does not mean the driver is missing.

## 2. Install RKLLama

Install the compiler and Python virtual-environment prerequisites:

```sh
sudo apt-get update
sudo apt-get install -y \
  python3-venv \
  python3-dev \
  build-essential \
  cmake \
  libcurl4-openssl-dev
```

Clone RKLLama and create an isolated Python environment:

```sh
git clone https://github.com/NotPunchnox/rkllama.git "$HOME/rkllama"
cd "$HOME/rkllama"
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install .
```

Run the final `pip install` from inside the repository. RKLLama's package metadata refers to its bundled RKNN wheel using a relative `./src/...` path, so a command such as `pip install /home/khadas/rkllama` can fail even though the wheel exists.

Verify the installation:

```sh
"$HOME/rkllama/.venv/bin/rkllama_server" --help
"$HOME/rkllama/.venv/bin/python" -m pip show rkllama
```

The deployment documented here used RKLLama commit `83891fba4783dfe1dc93ce0168b8e826983c126e`, package version `0.0.76`. To reproduce that exact version rather than the current default branch, check out the commit before running `pip install .`:

```sh
git checkout 83891fba4783dfe1dc93ce0168b8e826983c126e
```

## 3. Download Gemma 3 4B

Use a model already converted to RKLLM format for the RK3588. Converting the original Hugging Face model is normally done on a more powerful x86 host and is not required for this setup. See the Python scripts in [vlm-rknn](https://github.com/tristanpenman/vlm-rknn) for conversion steps. Alternatively, download a pre-converted model.

Create the model directory and download the tested W8A8_G128 conversion:

```sh
mkdir -p "$HOME/rkllama-models/gemma3-4b"
cd "$HOME/rkllama-models/gemma3-4b"

wget -c \
  -O gemma-3-4b-it_w8a8_g128_rk3588.rkllm \
  'https://huggingface.co/jamescallander/gemma-3-4b-it_w8a8_g128_rk3588.rkllm/resolve/main/gemma-3-4b-it_w8a8_g128_rk3588.rkllm'
```

The download is approximately 5.62 GB. `wget -c` allows an interrupted transfer to be resumed. Verify the artifact downloaded during the tested setup:

```sh
sha256sum gemma-3-4b-it_w8a8_g128_rk3588.rkllm
```

Expected checksum:

```text
5d38e049b6478c06258b2a62dea6ba112094e9eccfc1a2ed205e04ffd5423d3d
```

## 4. Create the Modelfile

Create `$HOME/rkllama-models/gemma3-4b/Modelfile`:

```text
FROM="gemma-3-4b-it_w8a8_g128_rk3588.rkllm"
HUGGINGFACE_PATH="unsloth/gemma-3-4b-it"
SYSTEM="You are a helpful assistant."
TEMPERATURE=0.7
TOP_P=0.9
TOP_K=40
MAX_TOKENS=512
```

`HUGGINGFACE_PATH` supplies the tokenizer and chat template. RKLLama downloads these on the first request and saves a local tokenizer directory beside the model. Internet access is therefore needed for the first inference unless the tokenizer has already been cached.

The resulting layout should be:

```text
/home/khadas/rkllama-models/
└── gemma3-4b/
    ├── Modelfile
    └── gemma-3-4b-it_w8a8_g128_rk3588.rkllm
```

The directory name, `gemma3-4b`, becomes the model name used in API requests.

## 5. Run RKLLama with systemd

RKLLama applies performance settings to CPU, GPU, DDR, and NPU sysfs controls when run as root. Install it as a root-owned system service by creating `/etc/systemd/system/rkllama.service`:

```ini
[Unit]
Description=RKLLama server on RK3588 NPU
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/khadas/rkllama
Environment=HOME=/home/khadas
Environment=HF_HOME=/home/khadas/.cache/huggingface
ExecStart=/home/khadas/rkllama/.venv/bin/rkllama_server --processor rk3588 --port 8080 --models /home/khadas/rkllama-models
Restart=on-failure
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```

Enable and start it:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now rkllama.service
sudo systemctl --no-pager --full status rkllama.service
```

Follow the logs with:

```sh
sudo journalctl -u rkllama.service -f
```

On a successful model load, the logs should identify the runtime, driver, platform, model conversion, and NPU core count. The tested setup reported:

```text
rkllm-runtime version: 1.3.0, rknpu driver version: 0.9.8, platform: RK3588
rkllm-toolkit version: 1.2.1, max_context_limit: 4096, npu_core_num: 3
model_dtype: W8A8_G128
```

## 6. Verify the API and inference

On the board, verify the server version and model inventory:

```sh
curl -fsS http://127.0.0.1:8080/api/version
curl -fsS http://127.0.0.1:8080/api/tags
```

`/api/tags` should contain a model named `gemma3-4b` with a size of `5621957124` bytes.

Run a non-streaming generation request:

```sh
curl --max-time 600 -sS http://127.0.0.1:8080/api/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma3-4b",
    "prompt": "Explain the RK3588 in one sentence.",
    "stream": false,
    "options": {
      "temperature": 0,
      "num_predict": 40
    }
  }'
```

The first request is substantially slower because RKLLama downloads the tokenizer and loads the 5.62 GB model. Later requests reuse the loaded model.

From another machine on the LAN, replace `<edge-2-address>` with the board's address:

```sh
curl -fsS http://<edge-2-address>:8080/api/tags

curl --max-time 120 -sS http://<edge-2-address>:8080/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma3-4b",
    "messages": [
      {"role": "user", "content": "Explain the RK3588 in one sentence."}
    ],
    "stream": false,
    "options": {
      "temperature": 0,
      "num_predict": 40
    }
  }'
```

RKLLama listens on `0.0.0.0:8080` by default, and these endpoints are compatible with the subset of the Ollama API used by Prompt Refinery.

## Operations and security

Useful service commands are:

```sh
sudo systemctl restart rkllama
sudo systemctl stop rkllama
sudo systemctl status rkllama
sudo journalctl -u rkllama --since '10 minutes ago'
```

Watch memory while the model is loaded:

```sh
watch -n 2 free -h
```

On the tested 8 GB Edge 2, memory use rose to approximately 5.9 GB after loading the model. The board had a 4 GB swap device, but inference did not materially use it. Heavy concurrency or a larger context can exhaust the remaining RAM.

RKLLama's HTTP server does not provide authentication or TLS in this configuration. Do not expose port 8080 to the public internet. Restrict it to a trusted LAN or place it behind an authenticated reverse proxy. Also replace the Khadas image's default login password before treating the device as a persistent network service.

## Troubleshooting

- If `pip` reports that `rknn_toolkit_lite2-...whl` does not exist, change into `$HOME/rkllama` and run `.venv/bin/python -m pip install .` there.
- If `/api/tags` is empty, check that the model has its own directory containing both `Modelfile` and the `.rkllm` file, and that `--models` points to the parent directory.
- If the first request fails while loading the tokenizer, verify internet access and that `unsloth/gemma-3-4b-it` is reachable from the board. Inspect `journalctl` for the underlying Transformers error.
- If model loading is killed or the board becomes unresponsive, stop other memory-heavy services, reduce concurrent requests, and confirm that swap is available. This 5.62 GB artifact is already close to the limit of an 8 GB board.
- If NPU initialization fails, compare the model's toolkit version, RKLLM runtime version, and kernel NPU driver reported in the logs. The combination verified here is toolkit 1.2.1, runtime 1.3.0, and driver 0.9.8.
