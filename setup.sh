#!/usr/bin/env bash
# setup.sh — one-command Wazuh setup on local Kubernetes (k3d)
#
# Usage:
#   ./setup.sh                          # interactive setup
#   CLUSTER_NAME=my-wazuh ./setup.sh    # custom cluster name
#   WAZUH_INDEXER_PASSWORD=MyPass ./setup.sh  # custom password
#
# What it does:
#   1. Checks all required tools are installed
#   2. Creates a k3d cluster (k3s in Docker)
#   3. Generates TLS certificates for all Wazuh components
#   4. Deploys Wazuh Indexer → Manager → Dashboard in order
#   5. Prints access credentials and URLs
#
# Optional env overrides:
#   CLUSTER_NAME              Cluster name (default: wazuh-local)
#   WAZUH_NAMESPACE           Kubernetes namespace (default: wazuh)
#   WAZUH_INDEXER_PASSWORD    Indexer/admin password (default: SecurePassword123!)
#   WAZUH_API_PASSWORD        Manager API password (default: SecurePassword123!)
#   WAZUH_DASHBOARD_PASSWORD  Dashboard kibanaserver password (default: SecurePassword123!)
#   POD_READY_TIMEOUT         Seconds to wait for pod readiness (default: 360)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/requirements.sh"
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
echo -e "${BOLD}                  local k8s edition${RESET}"
echo ""

# ── Checks ────────────────────────────────────────────────────────────────────
print_requirements_table
check_requirements

# ── Cluster ───────────────────────────────────────────────────────────────────
create_cluster

# ── Wazuh ─────────────────────────────────────────────────────────────────────
deploy_wazuh

log_section "Setup Complete"
echo ""
log_ok "Wazuh is running on your local k3d cluster."
echo ""
log_info "Quick commands:"
echo "  ./access.sh    — open the dashboard in your browser"
echo "  ./status.sh    — check health of all Wazuh components"
echo "  ./teardown.sh  — remove everything (cluster + data)"
echo ""
