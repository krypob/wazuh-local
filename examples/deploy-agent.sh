#!/usr/bin/env bash
# examples/deploy-agent.sh — deploy and monitor a test Wazuh agent inside the cluster
#
# Usage:
#   ./examples/deploy-agent.sh              # deploy agent and tail enrollment log
#   ./examples/deploy-agent.sh --remove     # remove the test agent pod

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

source "${ROOT_DIR}/scripts/common.sh"

WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
REMOVE=false
[[ "${1:-}" == "--remove" ]] && REMOVE=true

require_cluster

if [[ "$REMOVE" == true ]]; then
  log_section "Removing Test Agent"
  kubectl delete pod wazuh-test-agent \
    --namespace="${WAZUH_NAMESPACE}" \
    --ignore-not-found
  log_ok "Test agent removed."
  exit 0
fi

log_section "Deploying Test Wazuh Agent"

# ── Verify manager is up ───────────────────────────────────────────────────
if ! kubectl get pod \
    --namespace="${WAZUH_NAMESPACE}" \
    --selector=app=wazuh-manager \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | grep -q .; then
  log_error "Wazuh Manager is not running. Run ./setup.sh first."
  exit 1
fi

# ── Deploy agent pod ───────────────────────────────────────────────────────
log_info "Applying agent pod manifest..."
kubectl apply -f "${SCRIPT_DIR}/agent-pod.yaml"

log_info "Waiting for agent pod to be running..."
kubectl wait pod/wazuh-test-agent \
  --namespace="${WAZUH_NAMESPACE}" \
  --for=condition=ready \
  --timeout=120s

log_ok "Agent pod is running."

# ── Check enrollment ───────────────────────────────────────────────────────
echo ""
log_info "Agent enrollment log (last 30 lines):"
echo "──────────────────────────────────────────"
kubectl logs wazuh-test-agent \
  --namespace="${WAZUH_NAMESPACE}" \
  --tail=30 2>/dev/null || log_warn "No logs yet — agent may still be starting."

echo ""
log_info "To see the agent in the Dashboard:"
echo "  1. Run: ./access.sh"
echo "  2. Navigate to: Agents → All agents"
echo "  3. Look for: k8s-test-agent"
echo ""
log_info "Stream live logs:"
echo "  kubectl logs -f wazuh-test-agent -n ${WAZUH_NAMESPACE}"
echo ""
log_info "Remove the agent:"
echo "  ./examples/deploy-agent.sh --remove"
