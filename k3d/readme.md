# Honeylab Honeypot + IDS + SIEM — Quickstart & Overview

> **Project summary**
>
> This repository contains a Kubernetes-based honeypot proof-of-concept (PoC) called **Honeylab**. It runs a small, isolated honeynet (namespace `honeynet`) fronted by an NGINX + ModSecurity proxy, a Go-based honeypot service, network IDS (Suricata) and network log collectors. The security telemetry is centralized into a SIEM stack (Wazuh + OpenSearch + Dashboard) running in the `siem` namespace. Fluent Bit collects logs and forwards them to the indexer.

---

## Goals
- Provide a simple, reproducible PoC for honeypot + IDS + SIEM running locally with `k3d`.
- Keep network segmentation and least-privilege in mind: `honeynet`, `monitoring`, `siem` namespaces and Kubernetes NetworkPolicies.
- Show how to pin workloads to nodes by role labels (proxy, honeypot, siem) without using cloud node pools.
- Make it easy to use your local Docker images (via `k3d image import`) or a registry.

---

## High-level architecture
- **Client / Internet** → **ModSecurity proxy (NGINX)** (TLS termination, WAF) → **Honeypot service**
- **Suricata** (packet capture) runs on the nodes that host proxy & honeypot (hostNetwork)
- **Fluent Bit** (DaemonSet) tails logs from containers and hostPath files and forwards them to **OpenSearch (Wazuh indexer)**
- **Wazuh Manager** receives agent data (Wazuh agents run as DaemonSet in `monitoring`) and correlates events with logs in OpenSearch
- **Wazuh Dashboard** provides UI access to indexed data

Namespaces used:
- `honeynet` — proxy + honeypot
- `monitoring` — Suricata, Fluent Bit, Wazuh Agents
- `siem` — Wazuh Manager, OpenSearch (indexer), Dashboard

---

## Files of interest in this repo
- `k8s/minimal-with-wazuh-node-affinity-honeylab.yaml` — full Kubernetes manifest for PoC (Deployments, DaemonSets, Services, NetworkPolicies)
- `docker-compose.yml` (uploaded) — local Docker image references; useful to see image names and build contexts. Path referenced in this workspace: `/mnt/data/docker-compose.yml`.

---

## Prerequisites (local dev)
- Docker Desktop (WSL2 integration recommended)
- WSL2 (Ubuntu recommended) or Linux terminal
- `kubectl` installed and in PATH
- `k3d` installed
- `helm` (optional, for later improvements)

---

## Quick Start (commands)
Run these in WSL/terminal. They assume you will create a new cluster called `honeylab` and then apply the provided manifests.

### 1) Create the `honeylab` cluster
```bash
k3d cluster create honeylab --servers 1 --agents 3
kubectl get nodes -o wide
```

### 2) Label & (optional) taint nodes
Map nodes to roles (example):
- `k3d-honeylab-agent-0` → `role=proxy`
- `k3d-honeylab-agent-1` → `role=honeypot`
- `k3d-honeylab-agent-2` → `role=siem` (tainted to reserve it)

```bash
kubectl label node k3d-honeylab-agent-0 role=proxy
kubectl label node k3d-honeylab-agent-1 role=honeypot
kubectl label node k3d-honeylab-agent-2 role=siem
kubectl taint node k3d-honeylab-agent-2 dedicated=siem:NoSchedule
```

### 3) Build & import local images (if you have local Dockerfiles)
If you have local Dockerfiles and want to use built images without pushing to a registry:

```bash
# build locally (example)
docker build -t my-honeypot:dev ./honeypot
docker build -t my-nginx-modsec:dev ./modsec-proxy
# import into honeylab k3d cluster
k3d image import my-honeypot:dev my-nginx-modsec:dev -c honeylab
```

Alternatively, tag + push to a registry and use the registry image names in the manifests.

### 4) Apply the manifests
```bash
kubectl apply -f k8s/minimal-with-wazuh-node-affinity-honeylab.yaml
```

### 5) Force a restart if you update images or affinity
```bash
kubectl rollout restart deployment/modsec-proxy -n honeynet
kubectl rollout restart deployment/honeypot -n honeynet
kubectl rollout restart statefulset/wazuh-indexer -n siem
kubectl rollout restart deployment/wazuh-manager -n siem
```

### 6) Quick checks
```bash
kubectl get pods -A -o wide
kubectl get nodes --show-labels
# Port-forward to check services locally
kubectl port-forward svc/modsec-proxy -n honeynet 8080:80 &
curl -v http://localhost:8080/
kubectl port-forward svc/wazuh-indexer -n siem 9200:9200 &
curl -s http://localhost:9200/_cat/indices?v
```

---

## Wazuh agent registration (overview)
Wazuh agents must register with the Wazuh Manager. For PoC you can:
- Manually use the manager's `manage_agents` tool to create an agent key, then run `agent-auth` in agent pods.
- Automate registration using an initContainer or Job that runs `agent-auth -m wazuh-manager.siem.svc.cluster.local -k <key>` (store key in a Secret).

Manual example:
```bash
# exec into manager pod to run manage_agents (example)
kubectl exec -n siem deploy/wazuh-manager -- /bin/bash -c "/var/ossec/bin/manage_agents"
# on agent pod (or by exec), run agent-auth
kubectl exec -n monitoring <wazuh-agent-pod> -- /var/ossec/bin/agent-auth -m wazuh-manager.siem.svc.cluster.local -k <AGENT_KEY>
```

Check registered agents on the manager:
```bash
kubectl exec -n siem deploy/wazuh-manager -- /bin/bash -c "/var/ossec/bin/manage_agents -l"
```

---

## Logging & Fluent Bit
- Prefer `access_log /dev/stdout` and `error_log /dev/stderr` in nginx so container logs are available via `kubectl logs` and Fluent Bit can collect them.
- Fluent Bit is configured (in the manifests) to tail container logs and Suricata logs and forward to OpenSearch (index `fluent-bit` by default).
- For ModSecurity audit logs you may also mount an audit directory and have Fluent Bit tail `/var/log/modsec/*.log`.

---

## Important operational notes & caveats
- **Namespaces vs nodes:** namespaces (like `honeynet`) do not determine node placement. Node placement is done by `nodeAffinity`/`nodeSelector` and labels/taints on nodes.
- **Storage & PVCs:** the OpenSearch StatefulSet uses `local-path`. If PVCs were created previously, they may bind to other nodes — delete PVCs only if you accept losing test data or use snapshot/restore.
- **Suricata interface:** if Suricata captures nothing, exec into a Suricata pod and `ip a` to find the correct interface name, then update the DaemonSet args (the `-i` flag).
- **Privileged pods:** Suricata and Wazuh agents run privileged in this PoC. Limit RBAC and consider dedicated node pools or traffic mirroring for production.

---

## Troubleshooting (common commands)
- Pod pending: `kubectl describe pod <pod> -n <ns>`
- Pod logs: `kubectl logs -n <ns> <pod>`
- Check which node a pod runs on: `kubectl get pods -n <ns> -o wide`
- Inspect node labels: `kubectl get nodes --show-labels`
- Check OpenSearch indices: `curl -s http://localhost:9200/_cat/indices?v` (after port-forward)

---



