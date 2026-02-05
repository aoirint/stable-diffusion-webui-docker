# syntax=docker/dockerfile:1
ARG BASE_IMAGE=ubuntu:24.04
ARG PYTHON_VERSION=3.10
ARG UV_VERSION=0.9

# Download uv binary stage
FROM "ghcr.io/astral-sh/uv:${UV_VERSION}" AS uv-reference

# Build uv and Python base stage
FROM "${BASE_IMAGE}" AS uv-python-base

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV PYTHONUNBUFFERED=1

ARG UV_VERSION
COPY --from=uv-reference /uv /uvx /bin/

ENV UV_PYTHON_CACHE_DIR="/uv_python_cache"
ENV UV_PYTHON_INSTALL_DIR="/opt/python"
ENV PATH="${UV_PYTHON_INSTALL_DIR}/bin:${PATH}"

ARG PYTHON_VERSION
RUN --mount=type=cache,target=/uv_python_cache <<EOF
    uv python install "${PYTHON_VERSION}"
EOF


# Build Python virtual environment stage
FROM uv-python-base AS build-venv

RUN --mount=type=cache,id=apt-cache-build,target=/var/cache/apt \
    --mount=type=cache,id=apt-lists-build,target=/var/lib/apt/lists \
<<EOF
    apt-get update

    apt-get install -y \
        git
EOF

#  uv configuration
# - Generate bytecodes
# - Copy packages into virtual environment
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Install Python dependencies
COPY ./pyproject.toml uv.lock /work/
RUN --mount=type=cache,target=/root/.cache/uv <<EOF
    cd /work

    UV_PROJECT_ENVIRONMENT="/opt/python_venv" uv sync --frozen --no-dev --no-editable --no-install-project
EOF


# Runtime stage
FROM uv-python-base AS runtime

RUN --mount=type=cache,id=apt-cache-runtime,target=/var/cache/apt \
    --mount=type=cache,id=apt-lists-runtime,target=/var/lib/apt/lists \
<<EOF
    apt-get update

    apt-get install -y \
        git \
        libgl1 \
        libglib2.0-0 \
        google-perftools \
        bc
EOF

# Copy Python virtual environment from build stage
COPY --from=build-venv /opt/python_venv /opt/python_venv
ENV PATH="/home/user/.local/bin:/opt/python_venv/bin:${PATH}"

# Create a non-root user with a home directory
ARG USER_UID="1000"
ARG USER_GID="1000"
RUN <<EOF
    groupadd --non-unique --gid "${USER_GID}" "user"
    useradd --non-unique --uid "${USER_UID}" --gid "${USER_GID}" --create-home "user"
EOF

# Create working directory and data directory for runtime user
RUN <<EOF
    mkdir -p "/code/stable-diffusion-webui"
    chown -R "${USER_UID}:${USER_GID}" "/code/stable-diffusion-webui"

    mkdir "/data"
    chown -R "${USER_UID}:${USER_GID}" "/data"
    
    mkdir -p "/home/user/.cache/huggingface"
    chown -R "${USER_UID}:${USER_GID}" "/home/user/.cache"
EOF

# Switch to non-root user
USER "${USER_UID}:${USER_GID}"
WORKDIR "/code/stable-diffusion-webui"

# 2026-02-05 dev branch latest commit
ARG SD_WEBUI_URL="https://github.com/AUTOMATIC1111/stable-diffusion-webui"
ARG SD_WEBUI_VERSION="fd68e0c3846b07c637c3d57b0c38f06c8485a753"
RUN <<EOF
    git clone "${SD_WEBUI_URL}" .
    git checkout "${SD_WEBUI_VERSION}"

    python -m compileall .
EOF

RUN <<EOF
    mkdir "/code/stable-diffusion-webui/log"

    rm -rf "/code/stable-diffusion-webui/extensions"
    ln -s "/data/extensions" "/code/stable-diffusion-webui/extensions"
EOF

# webui.sh: Disable venv support
ENV venv_dir="-"

# webui.sh: Enable accelerate
ENV ACCELERATE="True"

# Initialize WebUI and exit
RUN <<EOF
    ./webui.sh --skip-torch-cuda-test --skip-install --exit
EOF

ENTRYPOINT [ "./webui.sh", "--skip-torch-cuda-test", "--skip-install", "--listen", "--data-dir", "/data" ]
