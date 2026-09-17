# ==============================================================================
# Stage 1: Build Python dependencies & ComfyUI
# ==============================================================================
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=0

ARG COMFYUI_VERSION=v0.30.0
ARG TORCH_CUDA_INDEX_URL="https://download.pytorch.org/whl/cu130"

# Python 3.12, git, ビルドツールのインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3.12-dev python3-pip git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# uv の導入
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# ComfyUI をバージョン固定で clone
RUN git clone --depth 1 --branch ${COMFYUI_VERSION} \
    https://github.com/comfy-org/ComfyUI.git /opt/ComfyUI

# venv の作成と Python 依存関係のインストール
ENV VIRTUAL_ENV=/opt/venv
ENV UV_HTTP_TIMEOUT=600
RUN uv venv $VIRTUAL_ENV --python /usr/bin/python3.12

# 1. PyTorch (cu130) の導入
RUN uv pip install torch torchvision torchaudio --index-url ${TORCH_CUDA_INDEX_URL}

# 2. ComfyUI 公式要件 + ユーティリティの導入
RUN uv pip install -r /opt/ComfyUI/requirements.txt \
    && uv pip install wait-for-it beautifulsoup4 aiohttp_retry

# 3. TensorRT 11.x (sm89 FP8 対応) & 変換ツールの導入 — 変更なし
RUN uv pip install \
    "tensorrt-cu13>=11.0.0,<11.2.0" \
    "tensorrt-cu13-libs>=11.0.0,<11.2.0" \
    polygraphy onnx


# ==============================================================================
# Stage 2: Final Image (CUDA 13.0.3 + cuDNN + Node.js)
# ==============================================================================
FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# タイムゾーン設定
RUN apt-get update && apt-get install -y --no-install-recommends tzdata && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    echo "Asia/Tokyo" > /etc/timezone && \
    rm -rf /var/lib/apt/lists/*

# 基本ツール、フォント（日本語含む）、OpenCV描画依存
# TRT apt は入れない: TRT 11.x の cuda13.0 向け debian は公開されていない
# (11.x は cuda12.9/13.2/13.3/13.4 のみ) ため base CUDA 13.0.3 の純度維持を優先。
# TRT 11.x ランタイムは pip tensorrt-cu13 (<11.2.0) で提供。trtexec が要る場合は
# local-repo deb (要NVIDIAログイン) を別途追加すること。
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip git tmux nano htop lsyncd ssh-client \
    build-essential python3.12 python3.12-venv \
    fonts-dejavu-core fonts-noto-core fonts-noto-cjk fonts-ubuntu \
    fonts-ipafont fonts-ipaexfont fontconfig \
    libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN fc-cache -fv

# Node.js 環境 (fnm 経由で Node 25 + Corepack)
ENV FNM_DIR=/opt/fnm PATH="/opt/fnm/aliases/default/bin:$PATH"
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /usr/local/bin --skip-shell \
 && fnm install 25 && fnm default 25 \
 && npm i -g corepack@latest && corepack enable \
 && chmod -R a+w /opt/fnm

# Stage 1 (builder) から venv と ComfyUI をコピー
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/ComfyUI /opt/ComfyUI

# Python パスの設定
ENV PATH="/opt/venv/bin:$PATH"
ENV VIRTUAL_ENV="/opt/venv"
ENV COMFYUI_PATH="/opt/ComfyUI"
ENV LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# カスタムノードの事前クローン (Manager / was-node-suite / devtools)
WORKDIR /opt/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/WASasquatch/was-node-suite-comfyui.git && \
    mkdir -p ComfyUI_devtools

WORKDIR /opt/ComfyUI

EXPOSE 8188
CMD ["python", "/opt/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8188"]
