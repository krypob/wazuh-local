#!/usr/bin/env bash
# teardown.sh — stop Wazuh and remove the local cluster
#
# Usage:
#   ./teardown.sh              # interactive, auto-detects mode
#   ./teardown.sh --all        # remove everything without prompts
#   ./teardown.sh --mode k8s
#   ./teardown.sh --mode colima
#
# Optional env overrides:
#   CLUSTER_NAME     k3d cluster name (default: wazuh-local)
#   COLIMA_PROFILE   Colima instance name (default: wazuh)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/colima.sh"
source "${SCRIPT_DIR}/scripts/cluster.sh"
source "${SCRIPT_DIR}/scripts/certs.sh"
source "${SCRIPT_DIR}/scripts/wazuh.sh"

# ── Flags ─────────────────────────────────────────────────────────────────────
REMOVE_ALL=false
TEARDOWN_MODE=""
prev_arg=""
for arg in "$@"; do
  if [[ "$prev_arg" == "--mode" ]]; then TEARDOWN_MODE="$arg"; fi
  case "$arg" in
    --all)    REMOVE_ALL=true ;;
    --mode=*) TEARDOWN_MODE="${arg#--mode=}" ;;
  esac
  prev_arg="$arg"
done

# Auto-detect from .wazuh-mode written by setup.sh
if [[ -z "$TEARDOWN_MODE" && -f "${SCRIPT_DIR}/.wazuh-mode" ]]; then
  TEARDOWN_MODE="$(cat "${SCRIPT_DIR}/.wazuh-mode")"
  log_info "Detected mode: ${TEARDOWN_MODE}"
fi

if [[ -z "$TEARDOWN_MODE" ]]; then
  log_section "Select Teardown Mode"
  echo -e "  ${BOLD}[1] Kubernetes${RESET}  (Docker Desktop + k3d)"
  echo -e "  ${BOLD}[2] Lightweight${RESET} (Colima + k3d)"
  echo -n "  Choose [1/2]: "
  read -r mode_input
  case "$mode_input" in
    1) TEARDOWN_MODE="k8s" ;;
    2) TEARDOWN_MODE="colima" ;;
    *) log_error "Invalid choice."; exit 1 ;;
  esac
fi

_confirm() {
  if [[ "$REMOVE_ALL" == true ]]; then return 0; fi
  ask_yes_no "$1" "n"
}

log_section "Wazuh Teardown (${TEARDOWN_MODE} mode)"

# ── Remove Wazuh manifests (both modes use kubectl) ───────────────────────────
if _confirm "Remove Wazuh manifests and data from the cluster?"; then
  if kubectl cluster-info &>/dev/null 2>&1; then
    remove_wazuh
  else
    log_warn "Cluster not reachable — skipping manifest removal."
  fi
fi

# ── Delete k3d cluster ────────────────────────────────────────────────────────
if _confirm "Delete the k3d cluster '${CLUSTER_NAME:-wazuh-local}'?"; then
  delete_cluster
fi

# ── Colima: also stop/delete the VM ──────────────────────────────────────────
if [[ "$TEARDOWN_MODE" == "colima" ]]; then
  if [[ "$REMOVE_ALL" == true ]]; then
    if _confirm "Delete the Colima VM '${COLIMA_PROFILE:-wazuh}'? (frees disk space)"; then
      delete_colima
    fi
  else
    if _confirm "Stop the Colima VM '${COLIMA_PROFILE:-wazuh}'? (keeps VM, frees CPU/RAM)"; then
      stop_colima
    fi
  fi
fi

rm -f "${SCRIPT_DIR}/.wazuh-mode"

log_section "Teardown Complete"
log_ok "Wazuh stopped and cluster removed."
