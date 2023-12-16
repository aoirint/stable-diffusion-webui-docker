# Stable Diffusion Web UI in Docker

- <https://github.com/AUTOMATIC1111/stable-diffusion-webui>

## Environments

- Ubuntu 20.04 or later
- [Docker Engine](https://docs.docker.com/engine/install/ubuntu/) 23.0 or later
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

## Usage
### 1. Build Docker image

```shell
sudo docker build -t aoirint/sd_webui .
```

### 2. Run Web UI

```shell
# Create permanent directories (UID:GID = 1000:1000)
mkdir -p ./data ./log ./cache/huggingface
sudo chown -R 1000:1000 ./data ./log ./cache

sudo docker run --gpus all --rm -it -v "./data:/data" -v "./log:/code/stable-diffusion-webui/log" -v "./cache/huggingface:/home/user/.cache/huggingface" -p "127.0.0.1:7860:7860/tcp" aoirint/sd_webui

# To install extensions via Web UI (DO NOT ALLOW PUBLIC ACCESS),
sudo docker run --gpus all --rm -it -v "./data:/data" -v "./log:/code/stable-diffusion-webui/log" -v "./cache/huggingface:/home/user/.cache/huggingface" -p "127.0.0.1:7860:7860/tcp" aoirint/sd_webui --enable-insecure-extension-access
```
