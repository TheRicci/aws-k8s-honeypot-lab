# Honeypot Lab - Kubernetes Deployment

> **A production-ready Kubernetes deployment for a comprehensive honeypot security lab with WAF, IDS, and SIEM integration.**

This directory contains all Kubernetes manifests and deployment scripts to run a complete honeypot infrastructure on AWS EKS (or any Kubernetes cluster). The lab includes deception services, network intrusion detection, log aggregation, and security monitoring.

---

## 🏗️ Architecture Overview

```
Internet → [ModSecurity WAF Proxy] → [Honeypot Services]
                ↓                           ↓
         [Suricata IDS]              [Zeek Network Monitor]
                ↓                           ↓
         [Fluent Bit] ────────────→ [Wazuh Indexer]
                ↓                           ↓
         [Wazuh Manager] ←────────── [Wazuh Dashboard]
```

### Components

- **Honeynet Namespace**: ModSecurity proxy + multi-protocol honeypot services
- **Monitoring Namespace**: Suricata, Zeek, Fluent Bit, Wazuh agents
- **SIEM Namespace**: Wazuh Manager, OpenSearch Indexer, Dashboard, Threat Central

---

## 📁 Directory Structure

```
cloud/k8s/
├── deploy.sh                    # Main deployment script
├── build-images.sh              # Docker image build & push
├── test-deployment.sh            # Validation & testing
│
├── namespaces/                   # Namespace definitions
├── configs/                      # ConfigMaps (nginx, modsecurity, suricata, zeek, wazuh)
├── secrets/                      # SSL certificate generation & secrets
│
├── proxy/                        # ModSecurity WAF proxy
│   ├── deployment.yaml
│   └── service.yaml
│
├── honeypot/                     # Honeypot services
│   ├── deployment.yaml
│   └── service.yaml
│
├── ids/                          # Intrusion Detection Systems
│   ├── suricata-daemonset.yaml
│   └── zeek-daemonset.yaml
│
├── siem/                         # Security Information & Event Management
│   ├── wazuh-manager.yaml
│   ├── wazuh-indexer.yaml
│   ├── wazuh-dashboard.yaml
│   ├── wazuh-agent-daemonset.yaml
│   ├── fluent-bit-daemonset.yaml
│   └── threat-central.yaml
│
├── networkpolicies/              # Network isolation policies
├── security/                     # Pod security policies & isolation
└── scheduling/                  # Node affinity test pods
```

---

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (EKS recommended)
- `kubectl` configured and connected
- Node labels: `role=proxy`, `role=honeypot`, `role=siem` (set by CloudFormation/Terraform)
- Container registry access (for custom images)

### Deploy Everything

```bash
# Run the automated deployment script
./deploy.sh
```

The script will:
1. Create namespaces (`honeynet`, `monitoring`, `siem`)
2. Apply security configurations
3. Generate SSL certificates (if needed)
4. Deploy SIEM infrastructure (Wazuh stack)
5. Deploy honeynet components (proxy + honeypot)
6. Deploy IDS components (Suricata, Zeek)
7. Apply network policies
8. Verify deployment status

### Manual Deployment

```bash
# 1. Namespaces
kubectl apply -f namespaces/

# 2. ConfigMaps
kubectl apply -f configs/

# 3. SSL Certificates
cd secrets && ./generate-certificates.sh && cd ..
kubectl apply -f secrets/ssl-secrets.yaml

# 4. SIEM (in order)
kubectl apply -f siem/wazuh-indexer.yaml
kubectl apply -f siem/wazuh-manager.yaml
kubectl apply -f siem/wazuh-dashboard.yaml
kubectl apply -f siem/fluent-bit-daemonset.yaml

# 5. Honeynet
kubectl apply -f proxy/
kubectl apply -f honeypot/

# 6. IDS
kubectl apply -f ids/

# 7. Network Policies
kubectl apply -f networkpolicies/
```

---

## 🔧 Configuration

### Node Labels & Taints

The deployment expects nodes with specific labels (set by infrastructure-as-code):

- **Proxy nodes**: `role=proxy` (public subnet, internet-facing)
- **Honeypot nodes**: `role=honeypot` (private subnet)
- **SIEM nodes**: `role=siem` with taint `dedicated=siem:NoSchedule` (private subnet, isolated)

### Image Registry

Update image references in deployments to point to your container registry:

```bash
# Build and push images
export REGISTRY=your-registry.com/honeylab
export TAG=latest
./build-images.sh

# Update deployments (or use sed/kustomize)
sed -i "s|image:.*|image: $REGISTRY/modsec-proxy:$TAG|g" proxy/deployment.yaml
```

### SSL Certificates

Self-signed certificates are generated automatically. For production:

1. Replace certificates in `secrets/ssl-secrets.yaml`
2. Or use cert-manager with Let's Encrypt
3. Update ACM certificate ARN in CloudFormation load balancer config

---

## 🔍 Accessing Services

### Wazuh Dashboard

```bash
# Port-forward
kubectl port-forward -n siem svc/wazuh-dashboard 5601:5601

# Or via LoadBalancer (if configured)
kubectl get svc -n siem wazuh-dashboard
# Access: https://<EXTERNAL-IP>:5601
# Default: admin / SecretPassword
```

### Honeypot Proxy

```bash
# Port-forward
kubectl port-forward -n honeynet svc/proxy-service 8080:80

# Or via LoadBalancer
kubectl get svc -n honeynet proxy-service
# Access: http://<EXTERNAL-IP>
```

### Wazuh Indexer (OpenSearch)

```bash
kubectl port-forward -n siem svc/wazuh-indexer 9200:9200
curl -u admin:SecretPassword https://localhost:9200/_cat/indices
```

---

## 🧪 Testing & Validation

```bash
# Run validation script
./test-deployment.sh

# Check pod status
kubectl get pods -A

# Check services
kubectl get svc -A

# View logs
kubectl logs -n honeynet deployment/modsec-proxy
kubectl logs -n siem deployment/wazuh-manager
kubectl logs -n siem daemonset/fluent-bit
```

### Test Honeypot

```bash
# Send test traffic
curl -k https://<proxy-ip>/
curl -k https://<proxy-ip>/test.php?id=1'OR'1'=1  # SQL injection attempt

# Check ModSecurity logs
kubectl exec -n honeynet deployment/modsec-proxy -- tail -f /var/log/modsec/audit.log

# Check Wazuh alerts
kubectl exec -n siem deployment/wazuh-manager -- tail -f /var/ossec/logs/alerts/alerts.json
```

---

## 🔒 Security Features

- **Network Policies**: Namespace isolation, default deny, explicit allow rules
- **Pod Security**: Restricted security contexts, non-root users where possible
- **Node Isolation**: SIEM nodes tainted and dedicated
- **TLS Encryption**: All inter-service communication encrypted
- **WAF Protection**: ModSecurity with OWASP CRS rules

---

## 📊 Monitoring & Logging

- **Fluent Bit**: Collects logs from all pods and forwards to OpenSearch
- **Wazuh Manager**: Correlates events, generates alerts
- **Wazuh Dashboard**: Visualization and alerting interface
- **Suricata/Zeek**: Network traffic analysis and packet capture

---

## 🛠️ Troubleshooting

### Pods Not Scheduling

```bash
# Check node labels
kubectl get nodes --show-labels | grep role

# Check taints
kubectl describe node <siem-node> | grep Taints

# Verify tolerations in SIEM deployments
kubectl get deployment wazuh-manager -n siem -o yaml | grep -A5 tolerations
```

### Services Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n honeynet

# Check pod readiness
kubectl get pods -n honeynet -o wide

# Test internal connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  wget -O- http://honeypot.honeynet.svc.cluster.local:80
```

### Wazuh Agent Not Registering

```bash
# Check agent logs
kubectl logs -n monitoring daemonset/wazuh-agent

# Verify manager connectivity
kubectl exec -n monitoring <wazuh-agent-pod> -- \
  nc -zv wazuh-manager.siem.svc.cluster.local 1515

# Manual registration (if needed)
kubectl exec -n siem deployment/wazuh-manager -- /var/ossec/bin/manage_agents -l
```

---

## 🔄 Updates & Maintenance

### Rolling Updates

```bash
# Update proxy
kubectl set image deployment/modsec-proxy modsec-proxy=registry/honeylab/modsec-proxy:v2.0 -n honeynet
kubectl rollout status deployment/modsec-proxy -n honeynet

# Update honeypot
kubectl set image deployment/honeypot honeypot=registry/honeylab/honeypot:v2.0 -n honeynet
```

### Scaling

```bash
# Scale proxy (if needed)
kubectl scale deployment/modsec-proxy --replicas=2 -n honeynet

# Scale honeypot
kubectl scale deployment/honeypot --replicas=3 -n honeynet
```

---

## 📚 Additional Resources

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [ModSecurity Reference](https://github.com/SpiderLabs/ModSecurity/wiki)
- [Suricata User Guide](https://suricata.readthedocs.io/)
- [OWASP CRS Rules](https://coreruleset.org/)

---

## 🧹 Cleanup

```bash
# Delete all resources
kubectl delete -f networkpolicies/
kubectl delete -f ids/
kubectl delete -f honeypot/
kubectl delete -f proxy/
kubectl delete -f siem/
kubectl delete -f configs/
kubectl delete -f namespaces/
```

---

## 📝 Notes

- **Storage**: Wazuh Indexer uses persistent volumes (EBS on AWS). Data persists across pod restarts.
- **Resource Limits**: Adjust CPU/memory requests/limits in deployments based on your cluster capacity.
- **High Availability**: For production, deploy multiple replicas and use StatefulSets for stateful services.
- **Backup**: Regularly backup Wazuh Indexer data and configuration.

---

**Built for security research, threat intelligence, and defensive security training.**
