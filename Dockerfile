# Ostris AI-Toolkit on Koyeb (H100/H200) — all-in-one image.
# Deploy: push this folder to a GitHub repo, then in Koyeb choose
# "GitHub" source with the Docker builder. Set the service port to 8675.
# Datasets/configs/trained outputs live on the instance's local disk —
# it is EPHEMERAL (wiped on redeploy/reschedule). Download trained LoRAs
# you want to keep.

# cu130 per upstream README. Host driver on Koyeb is CUDA 12.4-class, so
# cuda-compat-13-0 below provides the forward-compatible user-mode libcuda.
FROM pytorch/pytorch:2.13.0-cuda13.0-cudnn9-devel

# Ubuntu 24.04's pip refuses system-wide installs (PEP 668); allow them
ENV PIP_BREAK_SYSTEM_PACKAGES=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates cuda-compat-13-0 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 — the AI-Toolkit UI requires Node > 20
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone --depth 1 https://github.com/ostris/ai-toolkit.git

WORKDIR /app/ai-toolkit
# torch first, per upstream README (base image already ships it, but this
# pins the exact upstream-tested cu130 wheel set)
RUN pip install --no-cache-dir torch==2.13.0 torchvision==0.28.0 torchaudio==2.11.0 \
    --index-url https://download.pytorch.org/whl/cu130
RUN pip install --no-cache-dir -r requirements.txt

# Build the UI at image-build time (tsc worker + next build + prisma client).
# The SQLite db itself is created at container start (see start.sh) since
# the disk is ephemeral anyway.
RUN cd ui && npm run install_deps && npx prisma generate && npm run build

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 8675
CMD ["/app/start.sh"]
