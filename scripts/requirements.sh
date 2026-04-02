#!/usr/bin/env bash
# scripts/requirements.sh — preflight checks for all required tools and resources
# Sourced by setup.sh; not executed directly.

check_requirements() {
  log_section "Checking Requirements"

  local failed=0

  # ── Required tools ───────────────────────────────────────────────────────────
  local required_tools=("docker" "k3d" "kubectl" "helm" "openssl")
  for tool in "${required_tools[@]}"; do
    if has_cmd "$tool"; then
      log_ok "${tool} found ($(${tool} version 2>/dev/null | head -1 || echo 'ok'))"
    else
      log_error "${tool} is not installed or not in PATH."
      failed=1
    fi
  done

  # ── Docker running ────────────────────────────────────────────────────────────
  if has_cmd docker; then
    if ! docker info &>/dev/null; then
      log_error "Docker is installed but not running. Start Docker Desktop first."
      failed=1
    else
      # Check Docker memory allocation
      local docker_mem_bytes
      docker_mem_bytes=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
      local docker_mem_gb=$(( docker_mem_bytes / 1024 / 1024 / 1024 ))
      if [[ "$docker_mem_gb" -lt 5 ]]; then
        log_warn "Docker has only ~${docker_mem_gb} GB RAM allocated. Wazuh needs at least 6 GB."
        log_warn "Increase Docker Desktop memory in: Settings → Resources → Memory"
      else
        log_ok "Docker memory: ~${docker_mem_gb} GB (sufficient)"
      fi
    fi
  fi

  # ── kubectl version ───────────────────────────────────────────────────────────
  if has_cmd kubectl; then
    local kube_ver
    kube_ver=$(kubectl version --client --short 2>/dev/null | head -1 || kubectl version --client 2>/dev/null | head -1)
    log_info "kubectl: ${kube_ver}"
  fi

  # ── Helm version ──────────────────────────────────────────────────────────────
  if has_cmd helm; then
    local helm_ver
    helm_ver=$(helm version --short 2>/dev/null || echo 'unknown')
    log_info "helm: ${helm_ver}"
  fi

  if [[ "$failed" -eq 1 ]]; then
    echo ""
    log_error "Some requirements are missing. Install them and re-run setup.sh."
    log_info  "Installation hints:"
    echo "  brew install k3d kubectl helm openssl"
    echo "  Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
  fi

  log_ok "All requirements satisfied."
}

print_requirements_table() {
  log_section "Resource Requirements"
  echo ""
  printf "  %-20s %-15s %-15s\n" "Component" "CPU Request" "RAM Request"
  printf "  %-20s %-15s %-15s\n" "─────────────────" "───────────" "───────────"
  printf "  %-20s %-15s %-15s\n" "Wazuh Indexer"    "500m"        "512Mi"
  printf "  %-20s %-15s %-15s\n" "Wazuh Manager"    "250m"        "256Mi"
  printf "  %-20s %-15s %-15s\n" "Wazuh Dashboard"  "100m"        "256Mi"
  printf "  %-20s %-15s %-15s\n" "─────────────────" "───────────" "───────────"
  printf "  %-20s %-15s %-15s\n" "Total"             "~850m"       "~1Gi"
  echo ""
  log_info "Docker Desktop: allocate at least 6 GB RAM and 2 CPUs."
  echo ""
}
