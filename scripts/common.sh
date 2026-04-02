#!/usr/bin/env bash
# scripts/common.sh — shared colors, logging helpers, and utility functions
# Sourced by all top-level scripts; not executed directly.

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"; \
                echo -e "${BOLD}${CYAN}  $*${RESET}"; \
                echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"; }

# ── Utilities ─────────────────────────────────────────────────────────────────

# Check if a command exists
has_cmd() { command -v "$1" &>/dev/null; }

# Prompt yes/no — ask_yes_no "Question" "default (y|n)"
ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local yn_hint
  if [[ "$default" == "y" ]]; then yn_hint="[Y/n]"; else yn_hint="[y/N]"; fi
  echo -e -n "${BOLD}${prompt} ${yn_hint}:${RESET} "
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# Wait for a kubectl resource to be ready
# wait_for_ready <namespace> <resource/name> <timeout_seconds>
wait_for_ready() {
  local ns="$1"
  local resource="$2"
  local timeout="${3:-300}"
  log_info "Waiting for ${resource} in namespace ${ns} (timeout: ${timeout}s)..."
  if kubectl wait "${resource}" \
      --namespace="${ns}" \
      --for=condition=ready \
      --timeout="${timeout}s" &>/dev/null; then
    log_ok "${resource} is ready."
  else
    log_error "${resource} did not become ready within ${timeout}s."
    log_error "Run: kubectl describe ${resource} -n ${ns}"
    return 1
  fi
}

# Wait for all pods with a label selector to be ready
# wait_for_pods <namespace> <label_selector> <timeout_seconds>
wait_for_pods() {
  local ns="$1"
  local selector="$2"
  local timeout="${3:-300}"
  log_info "Waiting for pods (${selector}) in ${ns} (timeout: ${timeout}s)..."
  if kubectl wait pod \
      --namespace="${ns}" \
      --selector="${selector}" \
      --for=condition=ready \
      --timeout="${timeout}s"; then
    log_ok "Pods (${selector}) are ready."
  else
    log_error "Pods (${selector}) did not become ready within ${timeout}s."
    kubectl get pods -n "${ns}" --selector="${selector}"
    return 1
  fi
}

# Check that a Kubernetes cluster is reachable
require_cluster() {
  if ! kubectl cluster-info &>/dev/null 2>&1; then
    log_error "No Kubernetes cluster reachable."
    log_error "Run ./setup.sh first to create the cluster."
    exit 1
  fi
}
