# syntax=docker/dockerfile:1.14
ARG BASE_IMAGE="ubuntu:22.04"

# Download the Python standalone build
FROM ${BASE_IMAGE} AS download-python-stage

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


# Build the Python virtual environment
FROM ${BASE_IMAGE} AS build-python-venv-stage

ENV PYTHON_DIR="/opt/python"
COPY --chown=root:root --from=download-python-stage "${PYTHON_DIR}" "${PYTHON_DIR}"

ARG BUILDER_UID="999"
ARG BUILDER_GID="999"
ARG BUILDER_NAME="builder"
RUN <<EOF
    set -eu

    groupadd --non-unique --gid "${BUILDER_GID}" "${BUILDER_NAME}"
    useradd --non-unique --uid "${BUILDER_UID}" --gid "${BUILDER_GID}" --create-home "${BUILDER_NAME}"
EOF

ENV WORK_DIR="/work"
ENV UV_CACHE_DIR="/cache/uv"
ENV PYTHON_VENV_DIR="/opt/python_venv"
RUN <<EOF
    set -eu

    mkdir -p "${WORK_DIR}"

    mkdir -p "${UV_CACHE_DIR}"
    chown -R "${BUILDER_UID}:${BUILDER_GID}" "${UV_CACHE_DIR}"

    mkdir -p "${PYTHON_VENV_DIR}"
    chown -R "${BUILDER_UID}:${BUILDER_GID}" "${PYTHON_VENV_DIR}"
EOF

USER "${BUILDER_UID}:${BUILDER_GID}"
WORKDIR "${WORK_DIR}"
ENV PATH="/home/${BUILDER_NAME}/.local/bin:${PYTHON_DIR}/bin:${PATH}"

ARG UV_VERSION="0.6.14"
RUN <<EOF
    set -eu

    pip install --user "uv==${UV_VERSION}"
EOF

COPY --chown=root:root ./pyproject.toml ./uv.lock "${WORK_DIR}"
RUN --mount=type=cache,uid=${BUILDER_UID},gid=${BUILDER_GID},target=${UV_CACHE_DIR} <<EOF
    set -eu

    cd "${WORK_DIR}"
    uv venv "${PYTHON_VENV_DIR}"

    UV_PROJECT_ENVIRONMENT="${PYTHON_VENV_DIR}" uv sync
EOF


# Build the runtime image
FROM ${BASE_IMAGE} AS runtime-stage

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

ARG USER_UID="1000"
ARG USER_GID="1000"
ARG USER_NAME="user"
RUN <<EOF
    set -eu

    groupadd --non-unique --gid "${USER_GID}" "${USER_NAME}"
    useradd --non-unique --uid "${USER_UID}" --gid "${USER_GID}" --create-home "${USER_NAME}"
EOF

ENV PYTHON_PATH="/opt/python"
COPY --chown=root:root --from=download-python-stage "${PYTHON_PATH}" "${PYTHON_PATH}"

ENV PYTHON_VENV_PATH="/opt/python_venv"
COPY --chown=root:root --from=build-python-venv-stage "${PYTHON_VENV_PATH}" "${PYTHON_VENV_PATH}"
ENV PATH="/home/${USER_NAME}/.local/bin:${PYTHON_VENV_PATH}/bin:${PYTHON_PATH}/bin:${PATH}"

ENV PROJECT_DIR="/code/stable-diffusion-webui"
ENV DATA_DIR="/data"
RUN <<EOF
    set -eu

    mkdir -p "${PROJECT_DIR}"
    chown -R "${USER_UID}:${USER_GID}" "${PROJECT_DIR}"

    mkdir "${DATA_DIR}"
    chown -R "${USER_UID}:${USER_GID}" "${DATA_DIR}"
    
    mkdir -p "/home/${USER_NAME}/.cache/huggingface"
    chown -R "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.cache"
EOF

USER "${USER_UID}:${USER_GID}"

ARG SD_WEBUI_URL="https://github.com/AUTOMATIC1111/stable-diffusion-webui"
# v1.10.1
ARG SD_WEBUI_VERSION="82a973c04367123ae98bd9abdf80d9eda9b910e2"
RUN <<EOF
    set -eu

    git clone "${SD_WEBUI_URL}" "${PROJECT_DIR}"
    cd "${PROJECT_DIR}"
    git checkout "${SD_WEBUI_VERSION}"
EOF

RUN <<EOF
    set -eu

    mkdir "${PROJECT_DIR}/log"

    rm -rf "${PROJECT_DIR}/extensions"
    ln -s "${DATA_DIR}/extensions" "${PROJECT_DIR}/extensions"
EOF

WORKDIR "${PROJECT_DIR}"
ENV PYTHONUNBUFFERED="1"

# webui.sh: Disable venv support
ENV venv_dir="-"

# webui.sh: Enable accelerate
ENV ACCELERATE="True"

ENTRYPOINT [ "./webui.sh", "--skip-torch-cuda-test", "--listen", "--data-dir", "${DATA_DIR}", "--xformers" ]
