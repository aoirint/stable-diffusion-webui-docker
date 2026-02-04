# syntax=docker/dockerfile:1
ARG BASE_IMAGE="ubuntu:24.04"

# Pythonバイナリをダウンロードするステージ
FROM "${BASE_IMAGE}" AS download-python-stage

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND="noninteractive"

RUN <<EOF
    apt-get update

    apt-get install -y \
        wget \
        ca-certificates

    apt-get clean
    rm -rf /var/lib/apt/lists/*
EOF

ARG PYTHON_DATE="20260203"
ARG PYTHON_VERSION="3.10.19"
ARG PYTHON_SHA256_DIGEST="3397194408bd9afd3463a70313dc83d9d8abcf4beb37fc7335fa666a1501784c"
RUN <<EOF
    mkdir -p /opt/python-download

    cd /opt/python-download
    wget -O "python.tar.gz" "https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_DATE}/cpython-${PYTHON_VERSION}+${PYTHON_DATE}-x86_64-unknown-linux-gnu-install_only.tar.gz"
    echo "${PYTHON_SHA256_DIGEST} python.tar.gz" | sha256sum -c -

    # Extract to ./python
    tar xf "python.tar.gz"

    mv ./python /opt/python

    rm -f "python.tar.gz"
EOF


# Python仮想環境を構築するステージ
FROM "${BASE_IMAGE}" AS build-python-venv-stage

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND="noninteractive"

RUN <<EOF
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
    groupadd --non-unique --gid "${BUILDER_GID}" "builder"
    useradd --non-unique --uid "${BUILDER_UID}" --gid "${BUILDER_GID}" --create-home "builder"
EOF

# 作業用ユーザーが使用する作業ディレクトリと出力先ディレクトリを作成
RUN <<EOF
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
ARG UV_VERSION="0.9.29"
RUN <<EOF
    pip install --user "uv==${UV_VERSION}"
EOF

COPY ./pyproject.toml ./uv.lock /work/
RUN --mount=type=cache,uid="${BUILDER_UID}",gid="${BUILDER_GID}",target=/cache/uv <<EOF
    cd "/work"
    uv venv "/opt/python_venv"

    UV_PROJECT_ENVIRONMENT="/opt/python_venv" uv sync
EOF


# 実行用ステージ
FROM "${BASE_IMAGE}" AS runtime-stage

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND="noninteractive"

RUN <<EOF
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
    ln -s \
        /usr/local/cuda-11.8/targets/x86_64-linux/lib/libnvrtc.so.11.2 \
        /usr/local/cuda-11.8/targets/x86_64-linux/lib/libnvrtc.so
EOF

# ホームディレクトリを持つ実行用ユーザーを作成
ARG USER_UID="1000"
ARG USER_GID="1000"
RUN <<EOF
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
# 2026-02-05 dev branch latest commit
ARG SD_WEBUI_VERSION="fd68e0c3846b07c637c3d57b0c38f06c8485a753"
RUN <<EOF
    git clone "${SD_WEBUI_URL}" .
    git checkout "${SD_WEBUI_VERSION}"
EOF

RUN <<EOF
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
    ./webui.sh --skip-torch-cuda-test --skip-install --exit
EOF

ENTRYPOINT [ "./webui.sh", "--skip-torch-cuda-test", "--skip-install", "--listen", "--data-dir", "/data", "--xformers" ]
