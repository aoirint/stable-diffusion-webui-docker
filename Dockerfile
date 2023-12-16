# syntax=docker/dockerfile:1.6
ARG BASE_IMAGE=ubuntu:22.04
ARG BASE_RUNTIME_IMAGE=nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

FROM ${BASE_IMAGE} AS python-env

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ARG PIP_NO_CACHE_DIR=1
ARG PYENV_VERSION=v2.3.35
ARG PYTHON_VERSION=3.10.13

RUN <<EOF
    set -eu

    apt-get update

    apt-get install -y \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        curl \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        git

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

RUN <<EOF
    set -eu

    git clone https://github.com/pyenv/pyenv.git /opt/pyenv
    cd /opt/pyenv
    git checkout "${PYENV_VERSION}"

    PREFIX=/opt/python-build /opt/pyenv/plugins/python-build/install.sh
    /opt/python-build/bin/python-build -v "${PYTHON_VERSION}" /opt/python

    rm -rf /opt/python-build /opt/pyenv
EOF


FROM ${BASE_RUNTIME_IMAGE} AS runtime-env

ARG DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ARG PIP_NO_CACHE_DIR=1
ENV PATH=/home/user/.local/bin:/opt/python/bin:${PATH}

COPY --from=python-env /opt/python /opt/python

RUN <<EOF
    set -eu

    apt-get update

    apt-get install -y \
        git \
        gosu \
        libgl1 \
        libglib2.0-0 \
        google-perftools

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

RUN <<EOF
    set -eu

    groupadd -o -g 1000 user
    useradd -m -o -u 1000 -g user user
EOF

ARG SD_WEBUI_URL=https://github.com/AUTOMATIC1111/stable-diffusion-webui
# v1.7.0
ARG SD_WEBUI_VERSION=cf2772fab0af5573da775e7437e6acdca424f26e

RUN <<EOF
    set -eu

    mkdir -p /code
    chown -R user:user /code

    gosu user git clone "${SD_WEBUI_URL}" /code/stable-diffusion-webui
    cd /code/stable-diffusion-webui
    gosu user git checkout "${SD_WEBUI_VERSION}"
EOF

WORKDIR /code/stable-diffusion-webui

RUN <<EOF
    set -eu

    gosu user ./webui.sh --exit --skip-torch-cuda-test
EOF

RUN <<EOF
    set -eu

    gosu user venv/bin/pip3 install --no-cache-dir \
        onnxruntime-gpu==1.16.0 \
        xformers==0.0.22
EOF

RUN <<EOF
    set -eu

    mkdir /data
    chown -R user:user /data

    mkdir -p /home/user/.cache/huggingface
    chown -R user:user /home/user/.cache

    mkdir /code/stable-diffusion-webui/log
    chown -R user:user /code/stable-diffusion-webui/log

    rm -rf /code/stable-diffusion-webui/extensions
    ln -s /data/extensions /code/stable-diffusion-webui/extensions
EOF

ENTRYPOINT [ "gosu", "user", "./webui.sh", "--listen", "--data-dir", "/data", "--xformers" ]
