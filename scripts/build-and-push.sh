#!/usr/bin/env bash
# Build both Docker images and push them to Azure Container Registry.
# Usage:
#   ./scripts/build-and-push.sh <acr-name> [image-tag]
#
# Examples:
#   ./scripts/build-and-push.sh twolayeracrmyco123
#   ./scripts/build-and-push.sh twolayeracrmyco123 v1.2.3

set -euo pipefail

ACR_NAME="${1:-}"
IMAGE_TAG="${2:-latest}"

if [[ -z "$ACR_NAME" ]]; then
  echo "ERROR: ACR name is required." >&2
  echo "Usage: $0 <acr-name> [image-tag]" >&2
  exit 1
fi

ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
LAYER1_IMAGE="${ACR_LOGIN_SERVER}/layer1-batchapi:${IMAGE_TAG}"
LAYER2_IMAGE="${ACR_LOGIN_SERVER}/layer2-simulator:${IMAGE_TAG}"

# Resolve repo root relative to script location so the script works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> ACR:       ${ACR_LOGIN_SERVER}"
echo "==> Image tag: ${IMAGE_TAG}"
echo "==> Repo root: ${REPO_ROOT}"
echo ""

# ── Login ────────────────────────────────────────────────────────────────────
echo "==> Logging in to ACR..."
az acr login --name "${ACR_NAME}"

# ── Layer 2 ──────────────────────────────────────────────────────────────────
echo ""
echo "==> Building Layer2.Simulator -> ${LAYER2_IMAGE}"
docker build \
  -f "${REPO_ROOT}/Layer2.Simulator/Dockerfile" \
  -t "${LAYER2_IMAGE}" \
  "${REPO_ROOT}"

echo "==> Pushing ${LAYER2_IMAGE}..."
docker push "${LAYER2_IMAGE}"

# ── Layer 1 ──────────────────────────────────────────────────────────────────
echo ""
echo "==> Building Layer1.BatchApi -> ${LAYER1_IMAGE}"
docker build \
  -f "${REPO_ROOT}/Layer1.BatchApi/Dockerfile" \
  -t "${LAYER1_IMAGE}" \
  "${REPO_ROOT}"

echo "==> Pushing ${LAYER1_IMAGE}..."
docker push "${LAYER1_IMAGE}"

echo ""
echo "Done. Both images are available in ACR:"
echo "  ${LAYER2_IMAGE}"
echo "  ${LAYER1_IMAGE}"
