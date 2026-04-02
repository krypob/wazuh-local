#!/usr/bin/env bash
# teardown.sh — remove Wazuh and the local k3d cluster
#
# Usage:
#   ./teardown.sh          # interactive (asks before deleting cluster)
#   ./teardown.sh --all    # delete everything without prompts
#
# Optional env overrides:
#   CLUSTER_NAME     Cluster name to delete (default: wazuh-local)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/cluster.sh"
source "${SCRIPT_DIR}/scripts/certs.sh"
source "${SCRIPT_DIR}/scripts/wazuh.sh"

# ── Flags ─────────────────────────────────────────────────────────────────────
REMOVE_ALL=false
[[ "${1:-}" == "--all" ]] && REMOVE_ALL=true

_confirm() {
  local msg="$1"
  if [[ "$REMOVE_ALL" == true ]]; then return 0; fi
  ask_yes_no "$msg" "n"
}

# ── Teardown ──────────────────────────────────────────────────────────────────
log_section "Wazuh Teardown"

if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME:-wazuh-local}"; then
  log_warn "Cluster '${CLUSTER_NAME:-wazuh-local}' not found — nothing to remove."
  exit 0
fi

if _confirm "Remove Wazuh manifests and data from the cluster?"; then
  if kubectl cluster-info &>/dev/null 2>&1; then
    remove_wazuh
  else
    log_warn "Cluster not reachable — skipping manifest removal."
  fi
fi

if _confirm "Delete the k3d cluster '${CLUSTER_NAME:-wazuh-local}'? (All data will be lost)"; then
  delete_cluster
fi

log_section "Teardown Complete"
log_ok "All Wazuh resources have been removed."
