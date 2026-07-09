FROM nvidia/cuda:12.8.0-devel-ubuntu22.04

# 1. uv のインストール
COPY --from=ghcr.io/astral-sh/uv:0.9.2 /uv /uvx /usr/local/bin/

# 2. タイムゾーン設定
ENV TZ=Asia/Tokyo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 3. 必要なシステムパッケージのインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    nano \
    tmux \
    htop \
    libgl1 \
    libglib2.0-0 \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# 4. pyproject.toml を Dockerfile 内にベタ書きして生成
RUN cat << 'EOF' > pyproject.toml
[project]
name = "cosmos"
version = "0.1.0"
description = "Add your description here"
readme = "README.md"
requires-python = "~=3.12.0"
dependencies = [
    "torch==2.11.0",
    "torchvision==0.26.0",
    "torchaudio==2.11.0",
    "vllm",
    "vllm-omni",
    "cosmos-guardrail>=0.3.1",
]

[[tool.uv.index]]
name = "pytorch-cu128"
url = "https://download.pytorch.org/whl/cu128"
explicit = true

[tool.uv.sources]
torch = { index = "pytorch-cu128" }
torchvision = { index = "pytorch-cu128" }
torchaudio = { index = "pytorch-cu128" }
vllm = { git = "https://github.com/vllm-project/vllm.git", rev = "ee0da84ab9e04ac7610e28580af62c365e898389" }
vllm-omni = { git = "https://github.com/vllm-project/vllm-omni.git", rev = "d4a869fe5e2edd49af48026051948c8d1018d727" }
EOF

# 5. 仮想環境の設定
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# 6. ハブ転送エラー回避の環境変数をあらかじめ追加
ENV HF_HUB_ENABLE_HF_TRANSFER=0

# 7. コンテナのプラットフォーム（manylinux_x86_64）に合わせて自動でロック＆同期
# (あえて --frozen を外すことで、ホストの lock が無くても完璧な整合性で一発解決します)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync
