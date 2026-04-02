#!/usr/bin/env bash
# status.sh — health check for Wazuh
#
# Usage:
#   ./status.sh           # auto-detects mode, basic health check
#   ./status.sh --full    # deeper: indexer cluster health + agent list
#   ./status.sh --mode k8s
#   ./status.sh --mode colima

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"

WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
FULL=false
STATUS_MODE=""
prev_arg=""
for arg in "$@"; do
  if [[ "$prev_arg" == "--mode" ]]; then STATUS_MODE="$arg"; fi
  case "$arg" in
    --full)   FULL=true ;;
    --mode=*) STATUS_MODE="${arg#--mode=}" ;;
  esac
  prev_arg="$arg"
done

if [[ -z "$STATUS_MODE" && -f "${SCRIPT_DIR}/.wazuh-mode" ]]; then
  STATUS_MODE="$(cat "${SCRIPT_DIR}/.wazuh-mode")"
fi
STATUS_MODE="${STATUS_MODE:-k8s}"

require_cluster

log_section "Wazuh Status (${STATUS_MODE} mode)"

# ── Retrieve passwords ────────────────────────────────────────────────────────
INDEXER_PASS=$(kubectl get secret wazuh-passwords \
  --namespace="${WAZUH_NAMESPACE}" \
  --output=jsonpath='{.data.indexer-password}' 2>/dev/null \
  | base64 -d 2>/dev/null || echo "SecurePassword123!")
API_PASS=$(kubectl get secret wazuh-passwords \
  --namespace="${WAZUH_NAMESPACE}" \
  --output=jsonpath='{.data.api-password}' 2>/dev/null \
  | base64 -d 2>/dev/null || echo "SecurePassword123!")

# ── Pods ──────────────────────────────────────────────────────────────────────
echo ""
log_info "Pods:"
kubectl get pods --namespace="${WAZUH_NAMESPACE}" --output=wide 2>/dev/null \
  || log_warn "No pods found — is Wazuh deployed?"

echo ""
log_info "PVCs:"
kubectl get pvc --namespace="${WAZUH_NAMESPACE}" 2>/dev/null || true

echo ""
log_info "Services:"
kubectl get svc --namespace="${WAZUH_NAMESPACE}" 2>/dev/null || true

# ── Colima VM status ──────────────────────────────────────────────────────────
if [[ "$STATUS_MODE" == "colima" ]]; then
  echo ""
  log_info "Colima VM:"
  colima status --profile "${COLIMA_PROFILE:-wazuh}" 2>/dev/null || log_warn "Colima VM not running."
fi

# ── Manager API ping ──────────────────────────────────────────────────────────
echo ""
log_info "Manager API:"
if curl -sk -u "wazuh-wui:${API_PASS}" \
    "https://localhost:55000/" \
    --max-time 5 \
    -o /dev/null -w "  HTTP %{http_code}\n" 2>/dev/null; then
  log_ok "Manager API is reachable."
else
  log_warn "Manager API did not respond (may still be starting up)."
fi

# ── Full check ────────────────────────────────────────────────────────────────
if [[ "$FULL" == true ]]; then
  echo ""
  log_info "Indexer cluster health:"
  curl -sk -u "admin:${INDEXER_PASS}" \
    "https://localhost:9200/_cluster/health?pretty" \
    --max-time 5 2>/dev/null \
    | grep -E '"status"|"number_of_nodes"|"active_shards"' \
    | sed 's/^/  /' \
    || log_warn "Indexer not reachable on localhost:9200"

  echo ""
  log_info "Registered agents:"
  curl -sk -u "wazuh-wui:${API_PASS}" \
    "https://localhost:55000/agents?pretty" \
    --max-time 5 2>/dev/null \
    | grep -E '"id"|"name"|"status"' \
    | sed 's/^/  /' \
    || log_warn "Could not retrieve agent list."
fi

echo ""
log_info "Logs: kubectl logs -n ${WAZUH_NAMESPACE} <pod-name>"
