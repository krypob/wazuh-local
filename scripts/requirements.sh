#!/usr/bin/env bash
# scripts/requirements.sh — preflight checks, split by setup mode
# Sourced by setup.sh; not executed directly.

# ── k8s mode (Docker Desktop + k3d) ──────────────────────────────────────────
check_requirements_k8s() {
  log_section "Checking Requirements (k8s mode)"

  local failed=0
  local required_tools=("docker" "k3d" "kubectl" "helm" "openssl")
  for tool in "${required_tools[@]}"; do
    if has_cmd "$tool"; then
      log_ok "${tool} found"
    else
      log_error "${tool} is not installed or not in PATH."
      failed=1
    fi
  done

  _check_docker_running || failed=1
  _check_docker_memory 5 || true

  if has_cmd kubectl; then
    log_info "kubectl: $(kubectl version --client 2>/dev/null | head -1)"
  fi

  if [[ "$failed" -eq 1 ]]; then
    echo ""
    log_error "Missing requirements. Install and re-run setup.sh."
    echo "  brew install k3d kubectl helm openssl"
    echo "  Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
  fi

  log_ok "All k8s requirements satisfied."
}

print_requirements_table_k8s() {
  log_section "Resource Requirements (k8s mode)"
  echo ""
  printf "  %-20s %-12s %-12s\n" "Component"       "CPU"     "RAM"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "Wazuh Indexer"   "500m"    "1Gi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Manager"   "500m"    "512Mi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Dashboard" "250m"    "512Mi"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "Total"            "~1250m"  "~2Gi"
  echo ""
  log_info "Docker Desktop: allocate at least 6 GB RAM and 2 CPUs."
  echo ""
}

# ── colima mode (Colima + k3d) ────────────────────────────────────────────────
check_requirements_colima() {
  log_section "Checking Requirements (colima mode)"

  local failed=0
  local required_tools=("colima" "k3d" "kubectl" "helm" "openssl")
  for tool in "${required_tools[@]}"; do
    if has_cmd "$tool"; then
      log_ok "${tool} found"
    else
      log_error "${tool} is not installed or not in PATH."
      failed=1
    fi
  done

  if has_cmd kubectl; then
    log_info "kubectl: $(kubectl version --client 2>/dev/null | head -1)"
  fi

  if [[ "$failed" -eq 1 ]]; then
    echo ""
    log_error "Missing requirements. Install and re-run setup.sh."
    echo "  brew install colima k3d kubectl helm openssl"
    exit 1
  fi

  log_ok "All colima requirements satisfied."
}

print_requirements_table_colima() {
  log_section "Resource Requirements (colima mode)"
  echo ""
  printf "  %-20s %-12s %-12s\n" "Component"       "CPU"     "RAM"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "Colima VM"        "2 vCPU"  "6 GB"
  printf "  %-20s %-12s %-12s\n" "Wazuh Indexer"   "500m"    "1Gi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Manager"   "500m"    "512Mi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Dashboard" "250m"    "512Mi"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "VM total"         "2 vCPU"  "6 GB"
  echo ""
  log_info "Tune VM size via COLIMA_CPU / COLIMA_MEMORY env vars."
  echo ""
}

# ── Shared helpers ────────────────────────────────────────────────────────────
_check_docker_running() {
  if has_cmd docker && ! docker info &>/dev/null; then
    log_error "Docker is installed but not running. Start Docker Desktop first."
    return 1
  fi
  return 0
}

_check_docker_memory() {
  local min_gb="${1:-4}"
  if has_cmd docker && docker info &>/dev/null; then
    local mem_bytes
    mem_bytes=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
    local mem_gb=$(( mem_bytes / 1024 / 1024 / 1024 ))
    if [[ "$mem_gb" -lt "$min_gb" ]]; then
      log_warn "Docker has only ~${mem_gb} GB RAM. Recommended: ≥${min_gb} GB."
      log_warn "Increase in Docker Desktop: Settings → Resources → Memory"
    else
      log_ok "Docker memory: ~${mem_gb} GB (sufficient)"
    fi
  fi
  return 0
}
