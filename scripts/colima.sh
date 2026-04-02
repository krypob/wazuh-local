#!/usr/bin/env bash
# scripts/colima.sh — Colima VM lifecycle for wazuh-local (lightweight mode)
# Colima provides a lightweight Docker/k3s runtime without Docker Desktop.
# Sourced by setup.sh and teardown.sh; not executed directly.
#
# Env overrides:
#   COLIMA_PROFILE   Colima instance name (default: wazuh)
#   COLIMA_CPU       vCPUs to allocate   (default: 2)
#   COLIMA_MEMORY    RAM in GB           (default: 6)
#   COLIMA_DISK      Disk in GB          (default: 20)

COLIMA_PROFILE="${COLIMA_PROFILE:-wazuh}"
COLIMA_CPU="${COLIMA_CPU:-2}"
COLIMA_MEMORY="${COLIMA_MEMORY:-6}"
COLIMA_DISK="${COLIMA_DISK:-20}"

start_colima() {
  log_section "Starting Colima VM"

  if colima status --profile "${COLIMA_PROFILE}" &>/dev/null 2>&1; then
    log_warn "Colima profile '${COLIMA_PROFILE}' is already running — skipping start."
    _set_docker_context
    return 0
  fi

  log_info "Starting Colima (profile: ${COLIMA_PROFILE}, cpu: ${COLIMA_CPU}, mem: ${COLIMA_MEMORY}GB, disk: ${COLIMA_DISK}GB)..."
  colima start \
    --profile   "${COLIMA_PROFILE}" \
    --cpu       "${COLIMA_CPU}" \
    --memory    "${COLIMA_MEMORY}" \
    --disk      "${COLIMA_DISK}" \
    --runtime   docker \
    --network-address

  log_ok "Colima VM '${COLIMA_PROFILE}' started."
  _set_docker_context
}

stop_colima() {
  log_section "Stopping Colima VM"

  if ! colima status --profile "${COLIMA_PROFILE}" &>/dev/null 2>&1; then
    log_warn "Colima profile '${COLIMA_PROFILE}' is not running — nothing to stop."
    return 0
  fi

  log_info "Stopping Colima profile '${COLIMA_PROFILE}'..."
  colima stop --profile "${COLIMA_PROFILE}"
  log_ok "Colima VM '${COLIMA_PROFILE}' stopped."
}

delete_colima() {
  log_section "Deleting Colima VM"

  # Stop first if running
  if colima status --profile "${COLIMA_PROFILE}" &>/dev/null 2>&1; then
    log_info "Stopping Colima before deletion..."
    colima stop --profile "${COLIMA_PROFILE}"
  fi

  if colima list 2>/dev/null | grep -q "${COLIMA_PROFILE}"; then
    log_info "Deleting Colima profile '${COLIMA_PROFILE}'..."
    colima delete --profile "${COLIMA_PROFILE}" --force
    log_ok "Colima profile '${COLIMA_PROFILE}' deleted."
  else
    log_warn "Colima profile '${COLIMA_PROFILE}' not found — nothing to delete."
  fi
}

# Point the Docker context at Colima's socket so k3d uses it
_set_docker_context() {
  local context="colima-${COLIMA_PROFILE}"
  if docker context ls --format '{{.Name}}' 2>/dev/null | grep -q "^${context}$"; then
    docker context use "${context}" &>/dev/null
    log_info "Docker context set to: ${context}"
  else
    log_warn "Docker context '${context}' not found — Colima may not have registered it yet."
    log_warn "If k3d fails, run: docker context use colima-${COLIMA_PROFILE}"
  fi
}
