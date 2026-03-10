#!/usr/bin/env bash
# deploy.sh – build and deploy the Cartesi node to fly.io using Dockerfile.fly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE="${SCRIPT_DIR}/Dockerfile.node"
SNAPSHOT_DIR="${SCRIPT_DIR}/.cartesi/image"
APP="test-deploy323"
IMAGE="registry.fly.io/${APP}"

# ── sanity checks ─────────────────────────────────────────────────────────────
if [[ ! -f "${DOCKERFILE}" ]]; then
    echo "ERROR: Dockerfile.fly not found at ${DOCKERFILE}"
    exit 1
fi

if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
    echo "ERROR: Machine snapshot not found at ${SNAPSHOT_DIR}"
    echo "       Run 'cartesi build' first."
    exit 1
fi

# ── build ─────────────────────────────────────────────────────────────────────
echo "==> Authenticating with fly.io registry…"
fly auth docker

echo "==> Building node image (linux/amd64) from Dockerfile.fly…"
docker build \
    --platform linux/amd64 \
    -f "${DOCKERFILE}" \
    -t "${IMAGE}" \
    "${SNAPSHOT_DIR}"

echo "==> Pushing image to ${IMAGE}…"
docker push "${IMAGE}"

echo "==> Deploying to fly.io app '${APP}'…"
fly deploy --app "${APP}"

echo "==> Done. Run 'fly logs --app ${APP}' to watch startup."
