# syntax=docker/dockerfile:1.14
ARG BASE_IMAGE="ubuntu:22.04"
ARG BASE_RUNTIME_IMAGE=nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

# Pythonバイナリをダウンロードするステージ
FROM "${BASE_IMAGE}" AS download-python-stage

ARG DEBIAN_FRONTEND="noninteractive"
RUN <<EOF
    set -eu

    apt-get update

    apt-get install -y \
        wget \
        ca-certificates

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

ARG PYTHON_VERSION="3.10.17+20250409"
ARG PYTHON_SHA256_DIGEST="ba9e325b2d3ccacc1673f98aada0ee38f7d2d262c52253e2b36f745c9ae6e070"
RUN <<EOF
    set -eu

    mkdir -p /opt/python-download

    cd /opt/python-download
    wget -O "python.tar.gz" "https://github.com/astral-sh/python-build-standalone/releases/download/20250409/cpython-${PYTHON_VERSION}-x86_64-unknown-linux-gnu-install_only.tar.gz"
    echo "${PYTHON_SHA256_DIGEST} python.tar.gz" | sha256sum -c -

    # Extract to ./python
    tar xf "python.tar.gz"
    
    mv ./python /opt/python

    rm -f "python.tar.gz"
EOF


# Python仮想環境を構築するステージ
FROM "${BASE_IMAGE}" AS build-python-venv-stage

ARG DEBIAN_FRONTEND="noninteractive"
RUN <<EOF
    set -eu

    apt-get update

    apt-get install -y \
        git

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF


# ホームディレクトリを持つ作業用ユーザーを作成
ARG BUILDER_UID="999"
ARG BUILDER_GID="999"
RUN <<EOF
    set -eu

    groupadd --non-unique --gid "${BUILDER_GID}" "builder"
    useradd --non-unique --uid "${BUILDER_UID}" --gid "${BUILDER_GID}" --create-home "builder"
EOF

# 作業用ユーザーが使用する作業ディレクトリと出力先ディレクトリを作成
RUN <<EOF
    set -eu

    mkdir -p "/work"
    chown -R "${BUILDER_UID}:${BUILDER_GID}" "/work"

    mkdir -p "/cache/uv"
    chown -R "${BUILDER_UID}:${BUILDER_GID}" "/cache/uv"

    mkdir -p "/opt/python_venv"
    chown -R "${BUILDER_UID}:${BUILDER_GID}" "/opt/python_venv"
EOF

# Pythonをインストール
COPY --chown=root:root --from=download-python-stage /opt/python /opt/python
ENV PATH="/home/builder/.local/bin:/opt/python/bin:${PATH}"

# 作業用ユーザーに切り替え
USER "${BUILDER_UID}:${BUILDER_GID}"
WORKDIR "/work"

# uvをインストール
ARG UV_VERSION="0.6.14"
RUN <<EOF
    set -eu

    pip install --user "uv==${UV_VERSION}"
EOF

COPY ./pyproject.toml ./uv.lock /work/
RUN --mount=type=cache,uid="${BUILDER_UID}",gid="${BUILDER_GID}",target=/cache/uv <<EOF
    set -eu

    cd "/work"
    uv venv "/opt/python_venv"

    UV_PROJECT_ENVIRONMENT="/opt/python_venv" uv sync
EOF


# 実行用ステージ
FROM "${BASE_RUNTIME_IMAGE}" AS runtime-stage

ARG DEBIAN_FRONTEND="noninteractive"
RUN <<EOF
    set -eu

    apt-get update

    apt-get install -y \
        git \
        libgl1 \
        libglib2.0-0 \
        google-perftools \
        bc

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

# libnvrtc.so workaround
# https://github.com/aoirint/sd-scripts-docker/issues/19
RUN <<EOF
    set -eu

    ln -s \
        /usr/local/cuda-11.8/targets/x86_64-linux/lib/libnvrtc.so.11.2 \
        /usr/local/cuda-11.8/targets/x86_64-linux/lib/libnvrtc.so
EOF

# ホームディレクトリを持つ実行用ユーザーを作成
ARG USER_UID="1000"
ARG USER_GID="1000"
RUN <<EOF
    set -eu

    groupadd --non-unique --gid "${USER_GID}" "user"
    useradd --non-unique --uid "${USER_UID}" --gid "${USER_GID}" --create-home "user"
EOF

# Pythonをインストール
COPY --chown=root:root --from=download-python-stage /opt/python /opt/python

# Python仮想環境をインストール
COPY --chown=root:root --from=build-python-venv-stage /opt/python_venv /opt/python_venv
ENV PATH="/home/user/.local/bin:/opt/python_venv/bin:/opt/python/bin:${PATH}"

# 実行用ユーザーが使用する作業ディレクトリと出力先ディレクトリを作成
RUN <<EOF
    set -eu

    mkdir -p "/code/stable-diffusion-webui"
    chown -R "${USER_UID}:${USER_GID}" "/code/stable-diffusion-webui"

    mkdir "/data"
    chown -R "${USER_UID}:${USER_GID}" "/data"
    
    mkdir -p "/home/user/.cache/huggingface"
    chown -R "${USER_UID}:${USER_GID}" "/home/user/.cache"
EOF

# 作業用ユーザーに切り替え
USER "${USER_UID}:${USER_GID}"
WORKDIR "/code/stable-diffusion-webui"

ARG SD_WEBUI_URL="https://github.com/AUTOMATIC1111/stable-diffusion-webui"
# v1.10.1
ARG SD_WEBUI_VERSION="82a973c04367123ae98bd9abdf80d9eda9b910e2"
RUN <<EOF
    set -eu

    git clone "${SD_WEBUI_URL}" "/code/stable-diffusion-webui" .
    git checkout "${SD_WEBUI_VERSION}"
EOF

RUN <<EOF
    set -eu

    mkdir "/code/stable-diffusion-webui/log"

    rm -rf "/code/stable-diffusion-webui/extensions"
    ln -s "/data/extensions" "/code/stable-diffusion-webui/extensions"
EOF

# Python configuration
ENV PYTHONUNBUFFERED="1"

# webui.sh: Disable venv support
ENV venv_dir="-"

# webui.sh: Enable accelerate
ENV ACCELERATE="True"

# Initialize WebUI and exit
RUN <<EOF
    set -eu

    ./webui.sh --skip-torch-cuda-test --skip-install --exit
EOF

ENTRYPOINT [ "./webui.sh", "--skip-torch-cuda-test", "--skip-install", "--listen", "--data-dir", "/data", "--xformers" ]
