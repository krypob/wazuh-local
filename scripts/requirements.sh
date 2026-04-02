#!/usr/bin/env bash
# scripts/requirements.sh — preflight checks, split by setup mode
# Sourced by setup.sh; not executed directly.

# ── k8s mode checks ───────────────────────────────────────────────────────────
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

  _check_docker_running && _check_docker_memory 5 || failed=1

  if has_cmd kubectl; then
    log_info "kubectl: $(kubectl version --client 2>/dev/null | head -1)"
  fi

  if [[ "$failed" -eq 1 ]]; then
    echo ""
    log_error "Missing requirements. Install and re-run setup.sh."
    echo "  brew install k3d kubectl helm openssl"
    exit 1
  fi

  log_ok "All k8s requirements satisfied."
}

print_requirements_table_k8s() {
  log_section "Resource Requirements (k8s mode)"
  echo ""
  printf "  %-20s %-12s %-12s\n" "Component"       "CPU"    "RAM"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "Wazuh Indexer"   "500m"   "1Gi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Manager"   "500m"   "512Mi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Dashboard" "250m"   "512Mi"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "Total"            "~1250m" "~2Gi"
  echo ""
  log_info "Docker Desktop: allocate at least 6 GB RAM and 2 CPUs."
  echo ""
}

# ── compose mode checks ───────────────────────────────────────────────────────
check_requirements_compose() {
  log_section "Checking Requirements (compose mode)"

  local failed=0

  # docker
  if has_cmd docker; then
    log_ok "docker found"
  else
    log_error "docker is not installed or not in PATH."
    failed=1
  fi

  # docker compose (v2 plugin)
  if docker compose version &>/dev/null 2>&1; then
    log_ok "docker compose found ($(docker compose version --short 2>/dev/null || echo 'v2'))"
  else
    log_error "docker compose plugin not found. Install Docker Desktop >= 3.6 or 'docker-compose-plugin'."
    failed=1
  fi

  # openssl
  if has_cmd openssl; then
    log_ok "openssl found"
  else
    log_error "openssl is not installed. Install with: brew install openssl"
    failed=1
  fi

  _check_docker_running && _check_docker_memory 4 || failed=1

  if [[ "$failed" -eq 1 ]]; then
    echo ""
    log_error "Missing requirements. Install and re-run setup.sh."
    echo "  brew install openssl"
    echo "  Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
  fi

  log_ok "All compose requirements satisfied."
}

print_requirements_table_compose() {
  log_section "Resource Requirements (compose mode)"
  echo ""
  printf "  %-20s %-12s %-12s\n" "Component"       "CPU"    "RAM"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "Wazuh Indexer"   "~500m"  "512Mi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Manager"   "~200m"  "256Mi"
  printf "  %-20s %-12s %-12s\n" "Wazuh Dashboard" "~100m"  "256Mi"
  printf "  %-20s %-12s %-12s\n" "────────────────" "───────" "───────"
  printf "  %-20s %-12s %-12s\n" "Total"            "~800m"  "~1Gi"
  echo ""
  log_info "Docker Desktop: allocate at least 4 GB RAM."
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
