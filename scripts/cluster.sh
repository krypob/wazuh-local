#!/usr/bin/env bash
# scripts/cluster.sh — k3d cluster lifecycle for wazuh-local
# Sourced by setup.sh and teardown.sh; not executed directly.

# ── Defaults (override via env) ───────────────────────────────────────────────
CLUSTER_NAME="${CLUSTER_NAME:-wazuh-local}"
K3D_CONFIG_PATH="${K3D_CONFIG_PATH:-$(dirname "${BASH_SOURCE[0]}")/../configs/k3d-config.yaml}"

create_cluster() {
  log_section "Creating k3d Cluster"

  if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    log_warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
    k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default &>/dev/null
    log_ok "kubeconfig merged for existing cluster."
    return 0
  fi

  log_info "Creating cluster '${CLUSTER_NAME}' from ${K3D_CONFIG_PATH}..."
  k3d cluster create --config "${K3D_CONFIG_PATH}"

  log_info "Merging kubeconfig..."
  k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default

  log_info "Waiting for all nodes to be Ready..."
  kubectl wait node \
    --all \
    --for=condition=ready \
    --timeout=120s

  log_ok "Cluster '${CLUSTER_NAME}' is ready."
  kubectl get nodes -o wide
}

delete_cluster() {
  log_section "Deleting k3d Cluster"

  if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    log_warn "Cluster '${CLUSTER_NAME}' not found — nothing to delete."
    return 0
  fi

  log_info "Deleting cluster '${CLUSTER_NAME}'..."
  k3d cluster delete "${CLUSTER_NAME}"
  log_ok "Cluster '${CLUSTER_NAME}' deleted."
}
