#!/usr/bin/env bash
# access.sh — open the Wazuh Dashboard and print credentials
#
# Usage:
#   ./access.sh           # auto-detects mode
#   ./access.sh --api     # also print Manager API credentials
#   ./access.sh --mode k8s
#   ./access.sh --mode colima

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"

WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
SHOW_API=false
ACCESS_MODE=""
prev_arg=""
for arg in "$@"; do
  if [[ "$prev_arg" == "--mode" ]]; then ACCESS_MODE="$arg"; fi
  case "$arg" in
    --api)    SHOW_API=true ;;
    --mode=*) ACCESS_MODE="${arg#--mode=}" ;;
  esac
  prev_arg="$arg"
done

if [[ -z "$ACCESS_MODE" && -f "${SCRIPT_DIR}/.wazuh-mode" ]]; then
  ACCESS_MODE="$(cat "${SCRIPT_DIR}/.wazuh-mode")"
fi
ACCESS_MODE="${ACCESS_MODE:-k8s}"

require_cluster

log_section "Wazuh Dashboard Access"

# ── Retrieve passwords from cluster ──────────────────────────────────────────
INDEXER_PASS=$(kubectl get secret wazuh-passwords \
  --namespace="${WAZUH_NAMESPACE}" \
  --output=jsonpath='{.data.indexer-password}' 2>/dev/null \
  | base64 -d 2>/dev/null || echo "SecurePassword123!")
API_PASS=$(kubectl get secret wazuh-passwords \
  --namespace="${WAZUH_NAMESPACE}" \
  --output=jsonpath='{.data.api-password}' 2>/dev/null \
  | base64 -d 2>/dev/null || echo "SecurePassword123!")

# ── Print access info ─────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Mode:${RESET}           ${ACCESS_MODE}"
echo -e "  ${BOLD}Dashboard URL:${RESET}  https://localhost:443"
echo -e "  ${BOLD}Username:${RESET}       admin"
echo -e "  ${BOLD}Password:${RESET}       ${INDEXER_PASS}"
echo ""
echo -e "  ${YELLOW}Note: Accept the self-signed certificate warning in your browser.${RESET}"

if [[ "$SHOW_API" == true ]]; then
  echo ""
  echo -e "  ${BOLD}Manager API:${RESET}  https://localhost:55000"
  echo -e "  ${BOLD}API User:${RESET}     wazuh-wui"
  echo -e "  ${BOLD}API Pass:${RESET}     ${API_PASS}"
  echo ""
  echo "  Example:"
  echo "    curl -k -u wazuh-wui:${API_PASS} https://localhost:55000/"
fi

echo ""

# ── Open browser ──────────────────────────────────────────────────────────────
if has_cmd open; then
  open "https://localhost:443" &
elif has_cmd xdg-open; then
  xdg-open "https://localhost:443" &
else
  log_info "Open your browser: https://localhost:443"
fi

# ── Quick pod status ──────────────────────────────────────────────────────────
echo ""
log_info "Pod status:"
kubectl get pods --namespace="${WAZUH_NAMESPACE}" \
  --output=custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[-1].status" \
  2>/dev/null || true
echo ""
