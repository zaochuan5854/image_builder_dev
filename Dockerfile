FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

ARG TORCH_CUDA_INDEX_URL="https://download.pytorch.org/whl/cu128"

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    tzdata && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    echo "Asia/Tokyo" > /etc/timezone && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl git tmux nano htop lsyncd ssh-client fontconfig fonts-ipafont fonts-ipaexfont\
    && rm -rf /var/lib/apt/lists/*

RUN fc-cache -fv

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /opt
ENV UV_HTTP_TIMEOUT=600
RUN uv venv $VIRTUAL_ENV --python 3.12 --seed \
    && uv pip install torch torchvision torchaudio -v \
       --index-url ${TORCH_CUDA_INDEX_URL} \
    && uv pip install comfy-cli ComfyUI-EasyNodes beautifulsoup4 aiohttp_retry

RUN (echo y; echo n; echo y) | comfy --workspace /opt/comfyui install --nvidia --cuda-version 12.8\
    && comfy --workspace /opt/comfyui node install \
    ComfyUI-Manager \
    was-node-suite-comfyui

RUN cd /opt/comfyui/custom_nodes \
    && git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git

RUN cd /opt/comfyui/custom_nodes \
    && git clone https://github.com/rgthree/rgthree-comfy.git

RUN cd /opt/comfyui/custom_nodes \
    && git clone https://github.com/cosmicbuffalo/comfyui-mobile-frontend.git

ENV UV_INDEX_STRATEGY=unsafe-best-match
ARG CACHEBUST=1

RUN cd /opt/comfyui/custom_nodes \
    && git clone https://github.com/zaochuan5854/ComfyUI-TensorRT-Reforge.git \
    && cd ComfyUI-TensorRT-Reforge \
    && uv pip install -r requirements.txt

WORKDIR /opt/comfyui

ENV COMFYUI_PATH="/opt/comfyui"
