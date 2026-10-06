#!/usr/bin/env bash
# Idempotently run the kind local container registry and advertise it to the cluster.
# Follows https://kind.sigs.k8s.io/docs/user/local-registry/.
set -Eeuo pipefail

readonly REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
readonly REGISTRY_PORT="${REGISTRY_PORT:-5001}"
readonly REGISTRY_IMAGE="${REGISTRY_IMAGE:-registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373}"

# 1. Start the registry container unless it is already running.
if [ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null || true)" != "true" ]; then
  echo "starting registry ${REGISTRY_NAME} on localhost:${REGISTRY_PORT}"
  docker run -d --restart=always \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    --name "${REGISTRY_NAME}" "${REGISTRY_IMAGE}"
else
  echo "registry ${REGISTRY_NAME} already running"
fi

# 2. Attach the registry to the kind network so the cluster nodes can pull from it.
network="$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "${REGISTRY_NAME}" 2>/dev/null || true)"
if [ "${network}" = "null" ] || [ -z "${network}" ]; then
  if docker network inspect kind >/dev/null 2>&1; then
    echo "connecting ${REGISTRY_NAME} to the kind network"
    docker network connect kind "${REGISTRY_NAME}"
  else
    echo "kind network is not present yet; rerun after the cluster exists"
  fi
else
  echo "registry already attached to the kind network"
fi

# 3. Publish the local-registry-hosting ConfigMap so tooling can discover the registry.
if kubectl cluster-info >/dev/null 2>&1; then
  echo "applying local-registry-hosting ConfigMap"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
else
  echo "no reachable cluster; skipping local-registry-hosting ConfigMap"
fi

echo "registry ready at localhost:${REGISTRY_PORT} (in-cluster: ${REGISTRY_NAME}:5000)"
