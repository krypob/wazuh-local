#!/usr/bin/env bash
# access.sh — open the Wazuh Dashboard in your browser via port-forward
#
# Usage:
#   ./access.sh                # port-forward dashboard to https://localhost:8443
#   ./access.sh --api          # also show Wazuh API access info
#
# The dashboard is already exposed on https://localhost:443 via k3d port binding.
# This script opens the browser and prints credentials for convenience.
#
# Optional env overrides:
#   WAZUH_NAMESPACE    Kubernetes namespace (default: wazuh)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"

WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
SHOW_API=false
[[ "${1:-}" == "--api" ]] && SHOW_API=true

require_cluster

log_section "Wazuh Dashboard Access"

# ── Retrieve password from secret ─────────────────────────────────────────────
INDEXER_PASS=$(kubectl get secret wazuh-passwords \
  --namespace="${WAZUH_NAMESPACE}" \
  --output=jsonpath='{.data.indexer-password}' 2>/dev/null \
  | base64 -d 2>/dev/null || echo "SecurePassword123!")

API_PASS=$(kubectl get secret wazuh-passwords \
  --namespace="${WAZUH_NAMESPACE}" \
  --output=jsonpath='{.data.api-password}' 2>/dev/null \
  | base64 -d 2>/dev/null || echo "SecurePassword123!")

# ── Dashboard info ────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Dashboard URL:${RESET}  https://localhost:443"
echo -e "  ${BOLD}Username:${RESET}       admin"
echo -e "  ${BOLD}Password:${RESET}       ${INDEXER_PASS}"
echo ""
echo -e "  ${YELLOW}Note: Accept the self-signed certificate warning in your browser.${RESET}"
echo ""

if [[ "$SHOW_API" == true ]]; then
  echo -e "  ${BOLD}Manager API:${RESET}  https://localhost:55000"
  echo -e "  ${BOLD}API User:${RESET}     wazuh-wui"
  echo -e "  ${BOLD}API Pass:${RESET}     ${API_PASS}"
  echo ""
  echo "  Example API call:"
  echo "    curl -k -u wazuh-wui:${API_PASS} https://localhost:55000/"
  echo ""
fi

# ── Open browser ──────────────────────────────────────────────────────────────
if has_cmd open; then
  log_info "Opening dashboard in your default browser..."
  open "https://localhost:443" &
elif has_cmd xdg-open; then
  log_info "Opening dashboard in your default browser..."
  xdg-open "https://localhost:443" &
else
  log_info "Open your browser and navigate to: https://localhost:443"
fi

# ── Pod status quick check ────────────────────────────────────────────────────
echo ""
log_info "Current pod status:"
kubectl get pods --namespace="${WAZUH_NAMESPACE}" \
  --output=custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[-1].status"
echo ""
