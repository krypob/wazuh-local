#!/usr/bin/env bash
# setup.sh — one-command Wazuh setup on local Kubernetes
#
# Usage:
#   ./setup.sh                   # interactive — prompts for mode
#   ./setup.sh --mode k8s        # Standard:    Docker Desktop + k3d
#   ./setup.sh --mode colima     # Lightweight: Colima VM + k3d (no Docker Desktop)
#
# Optional env overrides (both modes):
#   WAZUH_INDEXER_PASSWORD    Indexer/admin password (default: SecurePassword123!)
#   WAZUH_API_PASSWORD        Manager API password (default: SecurePassword123!)
#   WAZUH_DASHBOARD_PASSWORD  Dashboard kibanaserver password (default: SecurePassword123!)
#   CLUSTER_NAME              Cluster name (default: wazuh-local)
#   WAZUH_NAMESPACE           Kubernetes namespace (default: wazuh)
#   POD_READY_TIMEOUT         Seconds to wait for pod readiness (default: 360)
#
# colima mode additional overrides:
#   COLIMA_PROFILE            Colima instance name (default: wazuh)
#   COLIMA_CPU                vCPUs (default: 2)
#   COLIMA_MEMORY             RAM in GB (default: 6)
#   COLIMA_DISK               Disk in GB (default: 20)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/requirements.sh"
source "${SCRIPT_DIR}/scripts/colima.sh"
source "${SCRIPT_DIR}/scripts/cluster.sh"
source "${SCRIPT_DIR}/scripts/certs.sh"
source "${SCRIPT_DIR}/scripts/wazuh.sh"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}  ██╗    ██╗ █████╗ ███████╗██╗   ██╗██╗  ██╗${RESET}"
echo -e "${BOLD}${CYAN}  ██║    ██║██╔══██╗╚══███╔╝██║   ██║██║  ██║${RESET}"
echo -e "${BOLD}${CYAN}  ██║ █╗ ██║███████║  ███╔╝ ██║   ██║███████║${RESET}"
echo -e "${BOLD}${CYAN}  ██║███╗██║██╔══██║ ███╔╝  ██║   ██║██╔══██║${RESET}"
echo -e "${BOLD}${CYAN}  ╚███╔███╔╝██║  ██║███████╗╚██████╔╝██║  ██║${RESET}"
echo -e "${BOLD}${CYAN}   ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝${RESET}"
echo -e "${BOLD}               local edition — v4.9.0${RESET}"
echo ""

# ── Parse --mode flag ─────────────────────────────────────────────────────────
SETUP_MODE=""
prev_arg=""
for arg in "$@"; do
  if [[ "$prev_arg" == "--mode" ]]; then SETUP_MODE="$arg"; fi
  case "$arg" in --mode=*) SETUP_MODE="${arg#--mode=}" ;; esac
  prev_arg="$arg"
done

# ── Interactive mode selection ────────────────────────────────────────────────
if [[ -z "$SETUP_MODE" ]]; then
  log_section "Select Setup Mode"
  echo ""
  echo -e "  ${BOLD}[1] Kubernetes${RESET}   — Docker Desktop + k3d."
  echo -e "      Requires: Docker Desktop, k3d, kubectl, helm, openssl"
  echo ""
  echo -e "  ${BOLD}[2] Lightweight${RESET}  — Colima + k3d. No Docker Desktop needed. ${GREEN}Recommended.${RESET}"
  echo -e "      Requires: colima, k3d, kubectl, helm, openssl"
  echo ""
  echo -n "  Choose [1/2] (default: 2): "
  read -r mode_input
  mode_input="${mode_input:-2}"

  case "$mode_input" in
    1) SETUP_MODE="k8s" ;;
    2) SETUP_MODE="colima" ;;
    *) log_error "Invalid choice. Use 1 or 2."; exit 1 ;;
  esac
fi

# Persist mode — read by teardown.sh / access.sh / status.sh
echo "${SETUP_MODE}" > "${SCRIPT_DIR}/.wazuh-mode"

# ── Mode: Kubernetes (Docker Desktop + k3d) ───────────────────────────────────
if [[ "$SETUP_MODE" == "k8s" ]]; then
  log_section "Mode: Kubernetes (Docker Desktop + k3d)"
  print_requirements_table_k8s
  check_requirements_k8s
  create_cluster
  deploy_wazuh
  log_section "Setup Complete"
  log_ok "Wazuh is running on your local k3d cluster (Docker Desktop)."

# ── Mode: Lightweight (Colima + k3d) ─────────────────────────────────────────
elif [[ "$SETUP_MODE" == "colima" ]]; then
  log_section "Mode: Lightweight (Colima + k3d)"
  print_requirements_table_colima
  check_requirements_colima
  start_colima
  create_cluster
  deploy_wazuh
  log_section "Setup Complete"
  log_ok "Wazuh is running on your local k3d cluster (Colima)."

else
  log_error "Unknown mode '${SETUP_MODE}'. Use: k8s | colima"
  exit 1
fi

echo ""
log_info "Quick commands:"
echo "  ./access.sh    — open the dashboard in your browser"
echo "  ./status.sh    — check health of all Wazuh components"
echo "  ./teardown.sh  — stop Wazuh (keeps data)"
echo "  ./teardown.sh --all — stop and remove all data"
echo ""
