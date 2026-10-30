#!/usr/bin/env bash
# AI-Toolkit startup for Koyeb: prepares the UI database, wires the HF
# token, then starts the worker + UI on port 8675.
set -uo pipefail

# CUDA 13 forward-compat: Koyeb's host driver is CUDA 12.4-class (< 580),
# too old for the cu130 runtime. The compat package ships a newer
# user-mode libcuda that forward-supports CUDA 13.0 on 535+ drivers.
if [ -d /usr/local/cuda-13.0/compat ]; then
  export LD_LIBRARY_PATH="/usr/local/cuda-13.0/compat:${LD_LIBRARY_PATH:-}"
fi

# HF token for gated training bases (FLUX.1-dev etc.). Set the HF_TOKEN
# secret in Koyeb and expose it as env var HF_TOKEN.
if [ -n "${HF_TOKEN:-}" ]; then
  export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
  export HF_HUB_ENABLE_HF_TRANSFER=1
  hf auth login --token "$HF_TOKEN" >/dev/null 2>&1 || true
fi

if [ -z "${AI_TOOLKIT_AUTH:-}" ]; then
  echo "WARNING: AI_TOOLKIT_AUTH is not set — the UI is OPEN to anyone with the URL."
  echo "         Set an AI_TOOLKIT_AUTH secret in Koyeb to password-protect it."
fi

cd /app/ai-toolkit/ui
# create/update the sqlite db on this instance's (ephemeral) disk
npx prisma db push

# --- HF dataset sync (massshare/zoo_v8): restore on boot, push every 5 min ---
# local datasets/  -> repo folder "dataset"   (note: SINGULAR in the repo.
#                     Includes latent/analysis cache stored next to the clips,
#                     so re-analysis is skipped after a redeploy)
# local output/    -> repo folder "outputs"   (trained LoRAs + samples)
SYNC_REPO="massshare/zoo_v8"
if [ -n "${HF_TOKEN:-}" ]; then
  # restore previous state (no-clobber: local files always win)
  TMP=/tmp/zoo_v8_restore
  echo "restoring datasets + outputs from $SYNC_REPO..."
  hf download "$SYNC_REPO" --repo-type dataset --local-dir "$TMP" \
    --token "$HF_TOKEN" >/dev/null 2>&1 || echo "restore: nothing to pull yet (or failed)"
  [ -d "$TMP/dataset" ]  && cp -rn "$TMP/dataset/."  /app/ai-toolkit/datasets/ 2>/dev/null
  [ -d "$TMP/outputs" ]  && cp -rn "$TMP/outputs/."  /app/ai-toolkit/output/
  rm -rf "$TMP"

  # push every 5 minutes — hf upload skips files already identical remotely
  (
    while true; do
      sleep 300
      if [ -d /app/ai-toolkit/datasets ]; then
        hf upload "$SYNC_REPO" /app/ai-toolkit/datasets dataset \
          --repo-type dataset --token "$HF_TOKEN" >/dev/null 2>&1 \
          && echo "[sync] datasets pushed" || echo "[sync] datasets push failed"
      fi
      if [ -d /app/ai-toolkit/output ]; then
        hf upload "$SYNC_REPO" /app/ai-toolkit/output outputs \
          --repo-type dataset --token "$HF_TOKEN" >/dev/null 2>&1 \
          && echo "[sync] outputs pushed" || echo "[sync] outputs push failed"
      fi
    done
  ) &
  echo "sync loop started: datasets + outputs -> $SYNC_REPO every 5 min"
else
  echo "HF_TOKEN not set - dataset/output sync disabled"
fi

echo "starting AI-Toolkit UI on port 8675..."
exec npm run start
