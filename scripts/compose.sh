#!/usr/bin/env bash
# scripts/compose.sh — Docker Compose lifecycle for Wazuh (lightweight mode)
# Sourced by setup.sh and teardown.sh; not executed directly.

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "${BASH_SOURCE[0]}")/../docker-compose.yml}"
WAZUH_INDEXER_PASSWORD="${WAZUH_INDEXER_PASSWORD:-SecurePassword123!}"
WAZUH_API_PASSWORD="${WAZUH_API_PASSWORD:-SecurePassword123!}"
WAZUH_DASHBOARD_PASSWORD="${WAZUH_DASHBOARD_PASSWORD:-SecurePassword123!}"

start_compose() {
  log_section "Starting Wazuh (Docker Compose)"

  # sysctl needed for OpenSearch
  if [[ "$(uname)" == "Linux" ]]; then
    log_info "Setting vm.max_map_count for OpenSearch..."
    sudo sysctl -w vm.max_map_count=262144 &>/dev/null || \
      log_warn "Could not set vm.max_map_count — indexer may fail to start."
  fi

  log_info "Pulling images and starting containers..."
  WAZUH_INDEXER_PASSWORD="${WAZUH_INDEXER_PASSWORD}" \
  WAZUH_API_PASSWORD="${WAZUH_API_PASSWORD}" \
  WAZUH_DASHBOARD_PASSWORD="${WAZUH_DASHBOARD_PASSWORD}" \
  docker compose -f "${COMPOSE_FILE}" up -d --wait 2>&1 \
    | grep -v "^#" | grep -v "^$" || true

  log_info "Waiting for all containers to be healthy..."
  local max_wait=300
  local elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    local unhealthy
    unhealthy=$(docker compose -f "${COMPOSE_FILE}" ps --format json 2>/dev/null \
      | grep -c '"Health":"starting"\|"Health":"unhealthy"' || true)
    [[ "$unhealthy" -eq 0 ]] && break
    sleep 5
    elapsed=$(( elapsed + 5 ))
    log_info "  Still waiting... (${elapsed}s / ${max_wait}s)"
  done

  if [[ $elapsed -ge $max_wait ]]; then
    log_warn "Some containers may not be fully healthy yet. Check: docker compose ps"
  fi

  log_ok "Wazuh containers are running."
  docker compose -f "${COMPOSE_FILE}" ps
  echo ""
  _print_compose_access_info
}

stop_compose() {
  log_section "Stopping Wazuh (Docker Compose)"

  if ! docker compose -f "${COMPOSE_FILE}" ps -q 2>/dev/null | grep -q .; then
    log_warn "No running Wazuh containers found — nothing to stop."
    return 0
  fi

  log_info "Stopping containers..."
  docker compose -f "${COMPOSE_FILE}" down
  log_ok "Wazuh containers stopped."
}

stop_compose_volumes() {
  log_section "Removing Wazuh (Docker Compose + volumes)"
  log_info "Removing containers and all data volumes..."
  docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
  log_ok "Wazuh containers and volumes removed."
}

_print_compose_access_info() {
  log_section "Wazuh is Ready (Compose Mode)"
  echo ""
  echo -e "  ${BOLD}Dashboard:${RESET}  https://localhost:443"
  echo -e "  ${BOLD}Username:${RESET}   admin"
  echo -e "  ${BOLD}Password:${RESET}   ${WAZUH_INDEXER_PASSWORD}"
  echo ""
  echo -e "  ${BOLD}Manager API:${RESET} https://localhost:55000"
  echo -e "  ${BOLD}API User:${RESET}   wazuh-wui"
  echo -e "  ${BOLD}API Pass:${RESET}   ${WAZUH_API_PASSWORD}"
  echo ""
  echo -e "  ${YELLOW}Note: Accept the self-signed certificate warning in your browser.${RESET}"
  echo ""
  log_info "Run ${BOLD}./access.sh${RESET} to open the dashboard."
  log_info "Run ${BOLD}./teardown.sh${RESET} to stop (keeps data) or ${BOLD}./teardown.sh --all${RESET} to remove data too."
  echo ""
}
