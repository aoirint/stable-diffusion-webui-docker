# Stable Diffusion Web UI in Docker

- <https://github.com/AUTOMATIC1111/stable-diffusion-webui>

## Environments

- Ubuntu 20.04 or later
- [Docker Engine](https://docs.docker.com/engine/install/ubuntu/) 23.0 or later
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

## Usage
### 1. Build Docker image

```shell
docker build . -t aoirint/sd_webui
```

### 2. Run Web UI

```shell
# Create a data directory (UID:GID = 1000:1000)
mkdir -p ./data

docker run --rm --gpus all -v "./data:/data" -p "127.0.0.1:7860:7860/tcp" aoirint/sd_webui

# To install extensions via Web UI (DO NOT ALLOW PUBLIC ACCESS),
docker run --rm --gpus all -v "./data:/data" -p "127.0.0.1:7860:7860/tcp" aoirint/sd_webui --enable-insecure-extension-access
```
