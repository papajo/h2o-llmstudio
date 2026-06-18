FROM python:3.10-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG GPU_SUPPORT=false

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        make \
        wget \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 nonroot

WORKDIR /workspace

# CUDA env vars — always set via ENV so they are available in the running
# container regardless of shell type.  On CPU builds the paths simply
# do not exist on disk and are harmless.
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}

# NVIDIA Container Toolkit runtime vars (set by nvidia-docker at
# launch, but providing defaults keeps the image self-documenting
# and ensures the vars are present even when the toolkit delegates.)
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

RUN python -m venv /workspace/venv

# Install uv and python dependencies
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# Ensure we run from the project root where pyproject.toml exists (copied later in this Dockerfile)
# We copy pyproject.toml earlier to make `uv sync` work.
COPY --chown=nonroot:nonroot ./pyproject.toml /workspace/pyproject.toml
COPY --chown=nonroot:nonroot ./uv.lock /workspace/uv.lock

# Install base dependencies (CUDA torch from uv.lock)
RUN cd /workspace && /root/.local/bin/uv sync --frozen --no-cache --no-dev

# For CPU-only builds, override torch with CPU wheels from PyTorch index
RUN if [ "$GPU_SUPPORT" = "false" ]; then \
        echo 'Installing CPU-only PyTorch...' && \
        cd /workspace && \
        /root/.local/bin/uv pip uninstall nvidia-cublas-cu12 nvidia-cuda-cupti-cu12 nvidia-cuda-nvrtc-cu12 nvidia-cuda-runtime-cu12 nvidia-cudnn-cu12 nvidia-cufft-cu12 nvidia-cufile-cu12 nvidia-curand-cu12 nvidia-cusolver-cu12 nvidia-cusparse-cu12 nvidia-cusparselt-cu12 nvidia-nccl-cu12 nvidia-nvjitlink-cu12 nvidia-nvtx-cu12 && \
        /root/.local/bin/uv pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cpu; \
    else \
        echo 'Using CUDA PyTorch (GPU support enabled)'; \
    fi

# Add the venv to the PATH
ENV PATH=/workspace/.venv/bin:$PATH

# We need to create a mount point for the user to mount their volume
# All persistent data lives in /mount
RUN mkdir -p /mount && chown -R nonroot:nonroot /mount
ENV H2O_LLM_STUDIO_WORKDIR=/mount

# Download the demo datasets and place in the /workspace/demo directory
# Set the environment variable for the demo datasets
ENV H2O_LLM_STUDIO_DEMO_DATASETS=/workspace/demo
COPY --chown=nonroot:nonroot ./llm_studio/download_default_datasets.py /workspace/
RUN python download_default_datasets.py

COPY --chown=nonroot:nonroot ./llm_studio /workspace/llm_studio
COPY --chown=nonroot:nonroot ./prompts /workspace/prompts
COPY --chown=nonroot:nonroot ./model_cards /workspace/model_cards
COPY --chown=nonroot:nonroot ./LICENSE /workspace/LICENSE
COPY --chown=nonroot:nonroot ./entrypoint.sh /workspace/entrypoint.sh

ENV HF_HOME=/mount/huggingface
ENV TRITON_CACHE_DIR=/mount/.triton/cache
ENV H2O_WAVE_DATA_DIR=/mount/wave_data
ENV HF_HUB_DISABLE_TELEMETRY=1
ENV DO_NOT_TRACK=1

# Set the environment variables for the wave server
ENV H2O_WAVE_APP_ADDRESS=http://127.0.0.1:8756
ENV H2O_WAVE_MAX_REQUEST_SIZE=25MB
ENV H2O_WAVE_NO_LOG=true
ENV H2O_WAVE_PRIVATE_DIR="/download/@/mount/output/download"

# Make the entrypoint.sh script executable
RUN chmod 755 /workspace/entrypoint.sh

EXPOSE 10101

USER nonroot

ENTRYPOINT [ "/workspace/entrypoint.sh" ]
