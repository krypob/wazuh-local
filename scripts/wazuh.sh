#!/usr/bin/env bash
# scripts/wazuh.sh — deploy and remove Wazuh components on Kubernetes
# Applies manifests in the correct order and waits for each component to be ready.
# Sourced by setup.sh and teardown.sh; not executed directly.

# ── Defaults (override via env) ───────────────────────────────────────────────
WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
MANIFESTS_DIR="${MANIFESTS_DIR:-$(dirname "${BASH_SOURCE[0]}")/../configs/wazuh}"
POD_READY_TIMEOUT="${POD_READY_TIMEOUT:-480}"

# ── Internal passwords (change for real environments) ─────────────────────────
WAZUH_INDEXER_PASSWORD="${WAZUH_INDEXER_PASSWORD:-SecurePassword123!}"
WAZUH_API_PASSWORD="${WAZUH_API_PASSWORD:-SecurePassword123!}"
WAZUH_DASHBOARD_PASSWORD="${WAZUH_DASHBOARD_PASSWORD:-SecurePassword123!}"

deploy_wazuh() {
  log_section "Deploying Wazuh"

  # ── Namespace ─────────────────────────────────────────────────────────────
  log_info "Creating namespace '${WAZUH_NAMESPACE}'..."
  kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"

  # ── Passwords Secret ──────────────────────────────────────────────────────
  log_info "Creating Wazuh credentials secret..."
  kubectl create secret generic wazuh-passwords \
    --namespace="${WAZUH_NAMESPACE}" \
    --from-literal=indexer-password="${WAZUH_INDEXER_PASSWORD}" \
    --from-literal=api-password="${WAZUH_API_PASSWORD}" \
    --from-literal=dashboard-password="${WAZUH_DASHBOARD_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

  # ── TLS Certificates ──────────────────────────────────────────────────────
  generate_certs

  # ── Storage ───────────────────────────────────────────────────────────────
  log_info "Applying storage configuration..."
  kubectl apply -f "${MANIFESTS_DIR}/storage.yaml"

  # ── Wazuh Indexer (OpenSearch) ────────────────────────────────────────────
  log_section "Deploying Wazuh Indexer"
  kubectl apply -f "${MANIFESTS_DIR}/indexer/"
  log_info "Waiting for Wazuh Indexer to start (this takes ~2 min)..."
  kubectl rollout status statefulset/wazuh-indexer \
    --namespace="${WAZUH_NAMESPACE}" \
    --timeout="${POD_READY_TIMEOUT}s"
  log_ok "Wazuh Indexer is running."

  # ── Initialize Indexer Security ───────────────────────────────────────────
  # Wait for OpenSearch HTTP to actually accept connections before running
  # securityadmin — the pod being Ready (TCP) doesn't mean the REST API is up.
  log_info "Waiting for OpenSearch REST API to accept connections..."
  _wait_for_indexer_http
  log_info "Initializing OpenSearch security (securityadmin)..."
  _run_security_admin

  # ── Wazuh Manager ─────────────────────────────────────────────────────────
  log_section "Deploying Wazuh Manager"
  kubectl apply -f "${MANIFESTS_DIR}/manager/"
  log_info "Waiting for Wazuh Manager to start..."
  kubectl rollout status statefulset/wazuh-manager \
    --namespace="${WAZUH_NAMESPACE}" \
    --timeout="${POD_READY_TIMEOUT}s"
  log_ok "Wazuh Manager is running."

  # ── Wazuh Dashboard ───────────────────────────────────────────────────────
  log_section "Deploying Wazuh Dashboard"
  kubectl apply -f "${MANIFESTS_DIR}/dashboard/"
  log_info "Waiting for Wazuh Dashboard to start..."
  kubectl rollout status deployment/wazuh-dashboard \
    --namespace="${WAZUH_NAMESPACE}" \
    --timeout="${POD_READY_TIMEOUT}s"
  log_ok "Wazuh Dashboard is running."

  print_access_info
}

# Poll until OpenSearch responds on port 9200 (even with a 401/403 — just
# means the HTTP listener is up). Needed because TCP-ready != HTTP-ready.
_wait_for_indexer_http() {
  local indexer_pod
  indexer_pod=$(kubectl get pod \
    --namespace="${WAZUH_NAMESPACE}" \
    --selector=app=wazuh-indexer \
    --output=jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  local max_wait=180
  local elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    local code
    code=$(kubectl exec "${indexer_pod}" \
      --namespace="${WAZUH_NAMESPACE}" \
      -- curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1:9200 2>/dev/null || echo "000")
    # 200/401/403 all mean the HTTP server is up
    if [[ "$code" == "200" || "$code" == "401" || "$code" == "403" ]]; then
      log_ok "OpenSearch HTTP is up (HTTP ${code})."
      return 0
    fi
    sleep 5
    elapsed=$(( elapsed + 5 ))
    log_info "  Still waiting for OpenSearch HTTP... (${elapsed}s / ${max_wait}s, last code: ${code})"
  done

  log_warn "OpenSearch HTTP did not respond within ${max_wait}s — proceeding anyway."
}

# Run the OpenSearch securityadmin script to initialize the security plugin.
# Must be run after the indexer pod is Ready.
_run_security_admin() {
  local indexer_pod
  indexer_pod=$(kubectl get pod \
    --namespace="${WAZUH_NAMESPACE}" \
    --selector=app=wazuh-indexer \
    --output=jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [[ -z "$indexer_pod" ]]; then
    log_warn "Could not find indexer pod — skipping securityadmin init."
    return 0
  fi

  log_info "Running securityadmin on pod ${indexer_pod}..."
  kubectl exec "${indexer_pod}" \
    --namespace="${WAZUH_NAMESPACE}" \
    -- bash -c \
    'JAVA_HOME=/usr/share/wazuh-indexer/jdk \
     chmod +x /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh && \
     /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
       -cd /usr/share/wazuh-indexer/opensearch-security/ \
       -nhnv \
       -cacert /usr/share/wazuh-indexer/certs/root-ca.pem \
       -cert /usr/share/wazuh-indexer/certs/admin.pem \
       -key /usr/share/wazuh-indexer/certs/admin-key.pem \
       -p 9200 \
       -h 127.0.0.1' \
    2>&1 | tail -5 || log_warn "securityadmin returned non-zero — may already be initialized."

  log_ok "Security initialization complete."
}

remove_wazuh() {
  log_section "Removing Wazuh"

  log_info "Removing Wazuh Dashboard..."
  kubectl delete -f "${MANIFESTS_DIR}/dashboard/" --ignore-not-found

  log_info "Removing Wazuh Manager..."
  kubectl delete -f "${MANIFESTS_DIR}/manager/" --ignore-not-found

  log_info "Removing Wazuh Indexer..."
  kubectl delete -f "${MANIFESTS_DIR}/indexer/" --ignore-not-found

  log_info "Removing storage and PVCs..."
  kubectl delete -f "${MANIFESTS_DIR}/storage.yaml" --ignore-not-found
  kubectl delete pvc --all --namespace="${WAZUH_NAMESPACE}" --ignore-not-found

  log_info "Removing secrets..."
  kubectl delete secret wazuh-passwords --namespace="${WAZUH_NAMESPACE}" --ignore-not-found

  log_info "Removing namespace..."
  kubectl delete -f "${MANIFESTS_DIR}/namespace.yaml" --ignore-not-found

  log_ok "Wazuh removed."
}

print_access_info() {
  local indexer_pass="${WAZUH_INDEXER_PASSWORD}"
  log_section "Wazuh is Ready"
  echo ""
  echo -e "  ${BOLD}Dashboard:${RESET}  https://localhost:443"
  echo -e "  ${BOLD}Username:${RESET}   admin"
  echo -e "  ${BOLD}Password:${RESET}   ${indexer_pass}"
  echo ""
  echo -e "  ${BOLD}Manager API:${RESET} https://localhost:55000"
  echo -e "  ${BOLD}API User:${RESET}   wazuh-wui"
  echo -e "  ${BOLD}API Pass:${RESET}   ${WAZUH_API_PASSWORD}"
  echo ""
  echo -e "  ${BOLD}Agent enrollment port:${RESET} localhost:1515"
  echo -e "  ${BOLD}Agent data port:${RESET}       localhost:1514"
  echo ""
  log_info "Run ${BOLD}./access.sh${RESET} to open the dashboard in your browser."
  echo ""
}
