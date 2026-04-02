#!/usr/bin/env bash
# scripts/certs.sh — TLS certificate generation for Wazuh components
# Generates self-signed certs for: indexer, manager, dashboard, admin.
#
# k8s mode:     uploads certs as Kubernetes Secrets in the wazuh namespace
# compose mode: writes certs to configs/compose/certs/ for volume mounts
#
# Sourced by setup.sh; not executed directly.

# ── Defaults (override via env) ───────────────────────────────────────────────
WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
CERTS_DIR="${CERTS_DIR:-/tmp/wazuh-certs}"
COMPOSE_CERTS_DIR="${COMPOSE_CERTS_DIR:-$(dirname "${BASH_SOURCE[0]}")/../configs/compose/certs}"
CERT_DAYS="${CERT_DAYS:-3650}"  # 10 years — fine for local dev

# ── Component list per mode ───────────────────────────────────────────────────
# k8s:     CN matches Kubernetes Service DNS
# compose: CN matches Docker Compose service hostname
_k8s_cert_components=(
  "indexer:wazuh-indexer.wazuh.svc.cluster.local"
  "manager:wazuh-manager.wazuh.svc.cluster.local"
  "dashboard:wazuh-dashboard.wazuh.svc.cluster.local"
  "admin:admin"
)
_compose_cert_components=(
  "indexer:wazuh-indexer"
  "manager:wazuh-manager"
  "dashboard:wazuh-dashboard"
  "admin:admin"
)

# ── Shared: generate root CA + component certs into CERTS_DIR ─────────────────
_generate_raw_certs() {
  local components=("$@")

  mkdir -p "${CERTS_DIR}"

  log_info "Generating Root CA..."
  openssl genrsa -out "${CERTS_DIR}/root-ca-key.pem" 2048 2>/dev/null
  openssl req -new -x509 -sha256 \
    -key "${CERTS_DIR}/root-ca-key.pem" \
    -out "${CERTS_DIR}/root-ca.pem" \
    -days "${CERT_DAYS}" \
    -subj "/C=US/ST=Local/L=Local/O=Wazuh/OU=Wazuh/CN=wazuh-root-ca" \
    2>/dev/null
  log_ok "Root CA generated."

  for entry in "${components[@]}"; do
    local name="${entry%%:*}"
    local cn="${entry##*:}"

    log_info "Generating cert for: ${name} (CN=${cn})..."
    openssl genrsa -out "${CERTS_DIR}/${name}-key.pem" 2048 2>/dev/null

    cat > "${CERTS_DIR}/${name}-san.cnf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${cn}
DNS.2 = ${name}
DNS.3 = localhost
IP.1  = 127.0.0.1
EOF

    openssl req -new -sha256 \
      -key "${CERTS_DIR}/${name}-key.pem" \
      -out "${CERTS_DIR}/${name}.csr" \
      -subj "/C=US/ST=Local/L=Local/O=Wazuh/OU=Wazuh/CN=${cn}" 2>/dev/null

    openssl x509 -req -sha256 \
      -in "${CERTS_DIR}/${name}.csr" \
      -CA "${CERTS_DIR}/root-ca.pem" \
      -CAkey "${CERTS_DIR}/root-ca-key.pem" \
      -CAcreateserial \
      -out "${CERTS_DIR}/${name}.pem" \
      -days "${CERT_DAYS}" \
      -extensions v3_req \
      -extfile "${CERTS_DIR}/${name}-san.cnf" 2>/dev/null

    log_ok "  ${name}.pem + ${name}-key.pem"
  done
}

# ── k8s mode: generate + upload to Kubernetes Secrets ────────────────────────
generate_certs() {
  log_section "Generating TLS Certificates (k8s mode)"

  if kubectl get secret wazuh-indexer-certs -n "${WAZUH_NAMESPACE}" &>/dev/null; then
    log_warn "TLS secrets already exist in namespace '${WAZUH_NAMESPACE}' — skipping."
    return 0
  fi

  _generate_raw_certs "${_k8s_cert_components[@]}"

  log_info "Uploading TLS secrets to namespace '${WAZUH_NAMESPACE}'..."

  kubectl create secret generic wazuh-indexer-certs \
    --namespace="${WAZUH_NAMESPACE}" \
    --from-file=root-ca.pem="${CERTS_DIR}/root-ca.pem" \
    --from-file=indexer.pem="${CERTS_DIR}/indexer.pem" \
    --from-file=indexer-key.pem="${CERTS_DIR}/indexer-key.pem" \
    --from-file=admin.pem="${CERTS_DIR}/admin.pem" \
    --from-file=admin-key.pem="${CERTS_DIR}/admin-key.pem"

  kubectl create secret generic wazuh-manager-certs \
    --namespace="${WAZUH_NAMESPACE}" \
    --from-file=root-ca.pem="${CERTS_DIR}/root-ca.pem" \
    --from-file=manager.pem="${CERTS_DIR}/manager.pem" \
    --from-file=manager-key.pem="${CERTS_DIR}/manager-key.pem"

  kubectl create secret generic wazuh-dashboard-certs \
    --namespace="${WAZUH_NAMESPACE}" \
    --from-file=root-ca.pem="${CERTS_DIR}/root-ca.pem" \
    --from-file=dashboard.pem="${CERTS_DIR}/dashboard.pem" \
    --from-file=dashboard-key.pem="${CERTS_DIR}/dashboard-key.pem"

  log_ok "TLS secrets uploaded to Kubernetes."
  rm -rf "${CERTS_DIR}"
}

# ── compose mode: generate + write to configs/compose/certs/ ──────────────────
generate_certs_compose() {
  log_section "Generating TLS Certificates (compose mode)"

  if [[ -f "${COMPOSE_CERTS_DIR}/root-ca.pem" ]]; then
    log_warn "Certs already exist at ${COMPOSE_CERTS_DIR} — skipping generation."
    return 0
  fi

  CERTS_DIR="${COMPOSE_CERTS_DIR}" _generate_raw_certs "${_compose_cert_components[@]}"
  # Clean up CSR and SAN tmp files, keep only the pems
  rm -f "${COMPOSE_CERTS_DIR}"/*.csr "${COMPOSE_CERTS_DIR}"/*.cnf "${COMPOSE_CERTS_DIR}"/*.srl
  log_ok "Certs written to ${COMPOSE_CERTS_DIR}."
}

delete_certs() {
  log_info "Removing TLS certificate secrets..."
  for secret in wazuh-indexer-certs wazuh-manager-certs wazuh-dashboard-certs; do
    kubectl delete secret "${secret}" --namespace="${WAZUH_NAMESPACE}" --ignore-not-found
  done
  log_ok "TLS secrets removed."
}

delete_certs_compose() {
  log_info "Removing compose certs from ${COMPOSE_CERTS_DIR}..."
  rm -f "${COMPOSE_CERTS_DIR}"/*.pem
  log_ok "Compose certs removed."
}
