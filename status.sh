#!/usr/bin/env bash
# status.sh — health check for Wazuh (auto-detects mode)
#
# Usage:
#   ./status.sh           # auto-detects mode, basic health check
#   ./status.sh --full    # deeper check: indexer health + agent list
#   ./status.sh --mode k8s
#   ./status.sh --mode compose

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/common.sh"

WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
FULL=false
STATUS_MODE=""

for arg in "$@"; do
  case "$arg" in
    --full)     FULL=true ;;
    --mode=*)   STATUS_MODE="${arg#--mode=}" ;;
  esac
done
for i in "$@"; do
  if [[ "${prev_arg:-}" == "--mode" ]]; then STATUS_MODE="$i"; fi
  prev_arg="$i"
done

# Auto-detect from .wazuh-mode
if [[ -z "$STATUS_MODE" && -f "${SCRIPT_DIR}/.wazuh-mode" ]]; then
  STATUS_MODE="$(cat "${SCRIPT_DIR}/.wazuh-mode")"
fi
STATUS_MODE="${STATUS_MODE:-compose}"

log_section "Wazuh Status (${STATUS_MODE} mode)"

# ── Get passwords ─────────────────────────────────────────────────────────────
if [[ "$STATUS_MODE" == "k8s" ]]; then
  require_cluster
  INDEXER_PASS=$(kubectl get secret wazuh-passwords \
    --namespace="${WAZUH_NAMESPACE}" \
    --output=jsonpath='{.data.indexer-password}' 2>/dev/null \
    | base64 -d 2>/dev/null || echo "SecurePassword123!")
  API_PASS=$(kubectl get secret wazuh-passwords \
    --namespace="${WAZUH_NAMESPACE}" \
    --output=jsonpath='{.data.api-password}' 2>/dev/null \
    | base64 -d 2>/dev/null || echo "SecurePassword123!")
else
  INDEXER_PASS="${WAZUH_INDEXER_PASSWORD:-SecurePassword123!}"
  API_PASS="${WAZUH_API_PASSWORD:-SecurePassword123!}"
fi

# ── k8s status ────────────────────────────────────────────────────────────────
if [[ "$STATUS_MODE" == "k8s" ]]; then
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

# ── compose status ────────────────────────────────────────────────────────────
else
  echo ""
  log_info "Containers:"
  docker compose -f "${SCRIPT_DIR}/docker-compose.yml" ps 2>/dev/null \
    || log_warn "No containers found — run ./setup.sh first."

  echo ""
  log_info "Resource usage:"
  docker stats --no-stream \
    wazuh-indexer wazuh-manager wazuh-dashboard 2>/dev/null \
    || true
fi

echo ""

# ── Manager API health (both modes) ──────────────────────────────────────────
log_info "Wazuh Manager API:"
if curl -sk -u "wazuh-wui:${API_PASS}" \
    "https://localhost:55000/" \
    --max-time 5 \
    -o /dev/null -w "  HTTP %{http_code}\n" 2>/dev/null; then
  log_ok "Manager API is reachable."
else
  log_warn "Manager API did not respond (may still be starting up)."
fi

if [[ "$FULL" == true ]]; then
  echo ""

  # Indexer cluster health
  log_info "Indexer cluster health:"
  curl -sk -u "admin:${INDEXER_PASS}" \
    "https://localhost:9200/_cluster/health?pretty" \
    --max-time 5 2>/dev/null \
    | grep -E '"status"|"number_of_nodes"|"active_shards"' \
    | sed 's/^/  /' \
    || log_warn "Indexer not reachable on localhost:9200"

  echo ""

  # Agent list
  log_info "Registered agents:"
  curl -sk -u "wazuh-wui:${API_PASS}" \
    "https://localhost:55000/agents?pretty" \
    --max-time 5 2>/dev/null \
    | grep -E '"id"|"name"|"status"' \
    | sed 's/^/  /' \
    || log_warn "Could not retrieve agent list."
fi

echo ""
if [[ "$STATUS_MODE" == "k8s" ]]; then
  log_info "Logs: kubectl logs -n ${WAZUH_NAMESPACE} <pod-name>"
else
  log_info "Logs: docker compose logs -f [wazuh-indexer|wazuh-manager|wazuh-dashboard]"
fi
