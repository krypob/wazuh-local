#!/usr/bin/env bash
# status.sh — health check for all Wazuh components
#
# Usage:
#   ./status.sh           # show pod status + quick API health ping
#   ./status.sh --full    # include indexer cluster health + agent list
#
# Optional env overrides:
#   WAZUH_NAMESPACE    Kubernetes namespace (default: wazuh)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"

WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
FULL=false
[[ "${1:-}" == "--full" ]] && FULL=true

require_cluster

log_section "Wazuh Status"

# ── Pod status ────────────────────────────────────────────────────────────────
echo ""
log_info "Pods in namespace '${WAZUH_NAMESPACE}':"
kubectl get pods --namespace="${WAZUH_NAMESPACE}" \
  --output=wide 2>/dev/null || log_warn "No pods found — is Wazuh deployed?"

echo ""

# ── PVC status ────────────────────────────────────────────────────────────────
log_info "Persistent volumes:"
kubectl get pvc --namespace="${WAZUH_NAMESPACE}" 2>/dev/null || true

echo ""

# ── Service status ────────────────────────────────────────────────────────────
log_info "Services:"
kubectl get svc --namespace="${WAZUH_NAMESPACE}" 2>/dev/null || true

echo ""

# ── API health check ──────────────────────────────────────────────────────────
API_PASS=$(kubectl get secret wazuh-passwords \
  --namespace="${WAZUH_NAMESPACE}" \
  --output=jsonpath='{.data.api-password}' 2>/dev/null \
  | base64 -d 2>/dev/null || echo "SecurePassword123!")

log_info "Wazuh Manager API health:"
if curl -sk -u "wazuh-wui:${API_PASS}" \
    "https://localhost:55000/" \
    --max-time 5 \
    -o /dev/null -w "  HTTP %{http_code}\n" 2>/dev/null; then
  log_ok "Manager API is reachable."
else
  log_warn "Manager API did not respond (may still be starting up)."
fi

echo ""

if [[ "$FULL" == true ]]; then
  # ── Indexer cluster health ─────────────────────────────────────────────────
  INDEXER_PASS=$(kubectl get secret wazuh-passwords \
    --namespace="${WAZUH_NAMESPACE}" \
    --output=jsonpath='{.data.indexer-password}' 2>/dev/null \
    | base64 -d 2>/dev/null || echo "SecurePassword123!")

  log_info "Indexer cluster health:"
  curl -sk -u "admin:${INDEXER_PASS}" \
    "https://localhost:9200/_cluster/health?pretty" \
    --max-time 5 2>/dev/null \
    | grep -E '"status"|"number_of_nodes"|"active_shards"' \
    | sed 's/^/  /' \
    || log_warn "Indexer not reachable on localhost:9200"

  echo ""

  # ── Agent list ────────────────────────────────────────────────────────────
  log_info "Registered agents:"
  curl -sk -u "wazuh-wui:${API_PASS}" \
    "https://localhost:55000/agents?pretty" \
    --max-time 5 2>/dev/null \
    | grep -E '"id"|"name"|"status"' \
    | sed 's/^/  /' \
    || log_warn "Could not retrieve agent list."

  echo ""
fi

log_info "For more detail: kubectl logs -n ${WAZUH_NAMESPACE} <pod-name>"
