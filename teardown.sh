#!/usr/bin/env bash
# teardown.sh — stop Wazuh (auto-detects mode from last setup.sh run)
#
# Usage:
#   ./teardown.sh              # stop containers/cluster, keep data volumes
#   ./teardown.sh --all        # stop + delete all data (irreversible)
#   ./teardown.sh --mode k8s   # force k8s teardown
#   ./teardown.sh --mode compose # force compose teardown
#
# Optional env overrides:
#   CLUSTER_NAME     k8s cluster name (default: wazuh-local)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/cluster.sh"
source "${SCRIPT_DIR}/scripts/certs.sh"
source "${SCRIPT_DIR}/scripts/wazuh.sh"
source "${SCRIPT_DIR}/scripts/compose.sh"

# ── Flags ─────────────────────────────────────────────────────────────────────
REMOVE_ALL=false
TEARDOWN_MODE=""

for arg in "$@"; do
  case "$arg" in
    --all)      REMOVE_ALL=true ;;
    --mode=*)   TEARDOWN_MODE="${arg#--mode=}" ;;
  esac
done
for i in "$@"; do
  if [[ "${prev_arg:-}" == "--mode" ]]; then TEARDOWN_MODE="$i"; fi
  prev_arg="$i"
done

# Auto-detect mode from .wazuh-mode file written by setup.sh
if [[ -z "$TEARDOWN_MODE" && -f "${SCRIPT_DIR}/.wazuh-mode" ]]; then
  TEARDOWN_MODE="$(cat "${SCRIPT_DIR}/.wazuh-mode")"
  log_info "Detected mode from last setup: ${TEARDOWN_MODE}"
fi

if [[ -z "$TEARDOWN_MODE" ]]; then
  log_section "Select Teardown Mode"
  echo -e "  ${BOLD}[1] Kubernetes (k3d)${RESET}"
  echo -e "  ${BOLD}[2] Lightweight (Compose)${RESET}"
  echo -n "  Choose [1/2]: "
  read -r mode_input
  case "$mode_input" in
    1) TEARDOWN_MODE="k8s" ;;
    2) TEARDOWN_MODE="compose" ;;
    *) log_error "Invalid choice."; exit 1 ;;
  esac
fi

_confirm() {
  local msg="$1"
  if [[ "$REMOVE_ALL" == true ]]; then return 0; fi
  ask_yes_no "$msg" "n"
}

# ── Teardown: k8s ─────────────────────────────────────────────────────────────
if [[ "$TEARDOWN_MODE" == "k8s" ]]; then
  log_section "Wazuh Teardown (k8s mode)"

  if _confirm "Remove Wazuh manifests from the cluster?"; then
    if kubectl cluster-info &>/dev/null 2>&1; then
      remove_wazuh
    else
      log_warn "Cluster not reachable — skipping manifest removal."
    fi
  fi

  if _confirm "Delete the k3d cluster '${CLUSTER_NAME:-wazuh-local}'? (All data will be lost)"; then
    delete_cluster
    rm -f "${SCRIPT_DIR}/.wazuh-mode"
  fi

# ── Teardown: compose ─────────────────────────────────────────────────────────
elif [[ "$TEARDOWN_MODE" == "compose" ]]; then
  log_section "Wazuh Teardown (compose mode)"

  if [[ "$REMOVE_ALL" == true ]]; then
    if _confirm "Stop containers AND delete all data volumes? (irreversible)"; then
      stop_compose_volumes
      delete_certs_compose
      rm -f "${SCRIPT_DIR}/.wazuh-mode"
    fi
  else
    if _confirm "Stop Wazuh containers? (data volumes are kept)"; then
      stop_compose
    fi
    log_info "Data volumes preserved. Run ${BOLD}./teardown.sh --all${RESET} to remove them."
  fi

else
  log_error "Unknown mode '${TEARDOWN_MODE}'. Use: k8s | compose"
  exit 1
fi

log_section "Teardown Complete"
log_ok "Wazuh stopped."
