# wazuh-local

One-command Wazuh deployment on local Kubernetes (k3d/k3s).

Runs the full Wazuh stack — **Indexer + Manager + Dashboard** — in a lightweight k3d cluster on your laptop. No cloud account, no Upbound, no external dependencies.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Scripts](#scripts)
- [Port Reference](#port-reference)
- [Resource Requirements](#resource-requirements)
- [Configuration](#configuration)
- [Test Agent](#test-agent)
- [Troubleshooting](#troubleshooting)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  k3d cluster: wazuh-local (k3s in Docker)                   │
│                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │ wazuh-indexer│   │ wazuh-manager│   │wazuh-dashboard │  │
│  │ (OpenSearch) │◄──│  (analysisd) │──►│  (web UI)      │  │
│  │  port: 9200  │   │ port: 1514   │   │  port: 5601    │  │
│  └──────────────┘   │ port: 1515   │   └────────────────┘  │
│        │            │ port: 55000  │          │             │
│       PVC           └──────────────┘         TLS           │
│                            │                               │
│                      PVC (data+logs)                       │
└─────────────────────────────────────────────────────────────┘
        │                    │                    │
  localhost:9200       localhost:1514        localhost:443
  (indexer API)        (agent data)         (dashboard)
                       localhost:1515
                       (enrollment)
                       localhost:55000
                       (manager API)
```

All components run as single replicas — right-sized for local development. TLS is self-signed and generated at setup time.

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | ≥ 24 | [docker.com](https://www.docker.com/products/docker-desktop) |
| k3d | ≥ 5.6 | `brew install k3d` |
| kubectl | ≥ 1.28 | `brew install kubectl` |
| helm | ≥ 3.14 | `brew install helm` |
| openssl | ≥ 3.x | `brew install openssl` |

**Docker Desktop RAM:** Set to at least **6 GB** in Settings → Resources → Memory.

---

## Quick Start

```bash
git clone https://github.com/krypob/wazuh-local.git
cd wazuh-local

./setup.sh
```

That's it. The script will:

1. Verify all prerequisites
2. Create a k3d cluster (`wazuh-local`)
3. Generate self-signed TLS certificates
4. Deploy Wazuh Indexer → Manager → Dashboard in order
5. Print access credentials

**Total setup time:** ~5–10 minutes (image pulls on first run).

### Access the Dashboard

```bash
./access.sh
```

Opens `https://localhost:443` — accept the self-signed cert warning.

| Field | Value |
|---|---|
| URL | https://localhost:443 |
| Username | `admin` |
| Password | `SecurePassword123!` (default) |

---

## Scripts

| Script | Description |
|---|---|
| `./setup.sh` | Full setup: cluster + TLS certs + Wazuh components |
| `./teardown.sh` | Remove everything (asks before deleting cluster) |
| `./teardown.sh --all` | Remove everything without prompts |
| `./access.sh` | Open dashboard in browser + print credentials |
| `./access.sh --api` | Also show Manager API credentials |
| `./status.sh` | Health check: pods, PVCs, services, API ping |
| `./status.sh --full` | Also check indexer cluster health + agent list |

---

## Port Reference

| Port | Protocol | Component | Purpose |
|---|---|---|---|
| `443` | HTTPS | Dashboard | Web UI access |
| `1514` | TCP | Manager | Agent data channel |
| `1515` | TCP | Manager | Agent auto-enrollment |
| `55000` | HTTPS | Manager | REST API |
| `9200` | HTTPS | Indexer | OpenSearch API (internal) |

---

## Resource Requirements

| Component | CPU Request | CPU Limit | RAM Request | RAM Limit |
|---|---|---|---|---|
| Wazuh Indexer | 250m | 500m | 512Mi | 1Gi |
| Wazuh Manager | 100m | 500m | 128Mi | 512Mi |
| Wazuh Dashboard | 50m | 250m | 128Mi | 512Mi |
| **Total** | **~400m** | **~1250m** | **~768Mi** | **~2Gi** |

**Docker Desktop:** Allocate at least **6 GB RAM** and **2 CPUs** for comfortable operation.

---

## Configuration

All scripts support environment variable overrides — no need to edit files.

```bash
# Custom cluster name
CLUSTER_NAME=my-wazuh ./setup.sh

# Custom passwords
WAZUH_INDEXER_PASSWORD=MyStrongPass ./setup.sh

# Longer timeout for slow machines
POD_READY_TIMEOUT=600 ./setup.sh
```

| Variable | Default | Description |
|---|---|---|
| `CLUSTER_NAME` | `wazuh-local` | k3d cluster name |
| `WAZUH_NAMESPACE` | `wazuh` | Kubernetes namespace |
| `WAZUH_INDEXER_PASSWORD` | `SecurePassword123!` | Indexer admin password |
| `WAZUH_API_PASSWORD` | `SecurePassword123!` | Manager API password |
| `WAZUH_DASHBOARD_PASSWORD` | `SecurePassword123!` | Dashboard kibanaserver password |
| `POD_READY_TIMEOUT` | `360` | Seconds to wait for pods |

---

## Test Agent

Deploy a containerized Wazuh agent inside the cluster to verify everything works end-to-end:

```bash
./examples/deploy-agent.sh
```

The agent auto-enrolls with the Manager and appears in the Dashboard under **Agents → All agents** as `k8s-test-agent`.

```bash
# Remove the test agent
./examples/deploy-agent.sh --remove

# Or connect an agent from your host machine:
docker run --rm \
  -e WAZUH_MANAGER=localhost \
  -e WAZUH_AGENT_NAME=host-agent \
  wazuh/wazuh-agent:4.9.0
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `docker: Cannot connect` | Docker not running | Start Docker Desktop |
| Indexer pod stuck in `Init:0/1` | `vm.max_map_count` too low | The init container sets this automatically — check Docker logs |
| Indexer pod OOMKilled | Not enough RAM | Increase Docker Desktop memory to ≥ 6 GB |
| Dashboard shows "Server not ready" | Indexer still starting | Wait 2–3 min and refresh |
| `certificate verify failed` in browser | Self-signed cert | Click "Advanced → Proceed" or add cert to trust store |
| Agent not appearing in Dashboard | Manager not running | Run `./status.sh` and check manager pod logs |
| Port already in use | Another service on 443/1514/1515 | Stop the conflicting service, then re-run `./setup.sh` |

**View pod logs:**
```bash
kubectl logs -n wazuh -l app=wazuh-indexer   --tail=50
kubectl logs -n wazuh -l app=wazuh-manager   --tail=50
kubectl logs -n wazuh -l app=wazuh-dashboard --tail=50
```

**Restart a component:**
```bash
kubectl rollout restart statefulset/wazuh-manager -n wazuh
kubectl rollout restart deployment/wazuh-dashboard -n wazuh
```

**Full reset:**
```bash
./teardown.sh --all && ./setup.sh
```
