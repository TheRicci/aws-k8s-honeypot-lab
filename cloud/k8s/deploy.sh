#!/bin/bash

# Complete deployment script for honeypot lab
# This script deploys all components in the correct order

set -e

echo "🚀 Deploying Honeypot Lab to Kubernetes..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    print_error "Kubernetes cluster not accessible. Please check your kubeconfig."
    exit 1
fi

print_success "Prerequisites check passed"

# Step 1: Create namespaces
print_status "Creating namespaces..."
kubectl apply -f namespaces/
print_success "Namespaces created"

# Step 2: Apply security configurations (basic)
print_status "Applying security configurations..."
kubectl apply -f security/siem-pod-security.yaml
print_success "Security configurations applied"

# Step 3: Create ConfigMaps
print_status "Creating ConfigMaps..."
kubectl apply -f configs/
print_success "ConfigMaps created"

# Step 4: Create SSL certificates and secrets
print_status "Setting up SSL certificates..."
# Check if certificates exist
if [ ! -f "secrets/certs/root-ca.pem" ]; then
    print_warning "SSL certificates not found. Generating self-signed certificates..."
    cd secrets
    chmod +x generate-certificates.sh
    ./generate-certificates.sh
    cd ..
fi

kubectl apply -f secrets/ssl-secrets.yaml
print_success "SSL certificates configured"

# Step 5: Deploy SIEM infrastructure (core services first)
print_status "Deploying SIEM infrastructure..."

# Deploy Wazuh Indexer first
print_status "Deploying Wazuh Indexer..."
kubectl apply -f siem/wazuh-indexer.yaml
kubectl wait --for=condition=available --timeout=300s deployment/wazuh-indexer -n siem
print_success "Wazuh Indexer deployed"

# Deploy Wazuh Manager
print_status "Deploying Wazuh Manager..."
kubectl apply -f siem/wazuh-manager.yaml
kubectl wait --for=condition=available --timeout=300s deployment/wazuh-manager -n siem
print_success "Wazuh Manager deployed"

# Deploy Wazuh Dashboard
print_status "Deploying Wazuh Dashboard..."
kubectl apply -f siem/wazuh-dashboard.yaml
kubectl wait --for=condition=available --timeout=300s deployment/wazuh-dashboard -n siem
print_success "Wazuh Dashboard deployed"

# Deploy Fluent Bit
print_status "Deploying Fluent Bit..."
kubectl apply -f siem/fluent-bit-daemonset.yaml
print_success "Fluent Bit deployed"

# Deploy Threat Central
print_status "Deploying Threat Central..."
kubectl apply -f siem/threat-central.yaml
kubectl wait --for=condition=available --timeout=60s deployment/threat-central -n siem
print_success "Threat Central deployed"

# Step 6: Deploy honeynet components
print_status "Deploying honeynet components..."

# Deploy honeypot
print_status "Deploying Honeypot..."
kubectl apply -f honeypot/
kubectl wait --for=condition=available --timeout=60s deployment/honeypot -n honeynet
print_success "Honeypot deployed"

# Deploy ModSec proxy
print_status "Deploying ModSec Proxy..."
kubectl apply -f proxy/
kubectl wait --for=condition=available --timeout=60s deployment/modsec-proxy -n honeynet
print_success "ModSec Proxy deployed"

# Deploy IDS components
print_status "Deploying IDS components..."
kubectl apply -f ids/
print_success "IDS components deployed"

# Step 7: Deploy Wazuh agent
print_status "Deploying Wazuh Agent..."
kubectl apply -f siem/wazuh-agent-daemonset.yaml
print_success "Wazuh Agent deployed"

# Step 8: Apply network policies
print_status "Applying network policies..."
kubectl apply -f networkpolicies/
print_success "Network policies applied"

# Step 9: Apply advanced security (optional)
print_status "Applying advanced security configurations..."
kubectl apply -f security/istio-security.yaml 2>/dev/null || print_warning "Istio not installed, skipping Istio security"
kubectl apply -f security/siem-monitoring.yaml 2>/dev/null || print_warning "Monitoring tools not installed, skipping monitoring rules"

print_success "Advanced security configurations applied"

# Final status check
print_status "Performing final deployment verification..."

echo ""
echo "========================================"
echo "🏁 DEPLOYMENT SUMMARY"
echo "========================================"

# Check pod status
echo ""
echo "Pod Status:"
kubectl get pods -A --field-selector=status.phase!=Succeeded

# Check service status
echo ""
echo "Service Status:"
kubectl get svc -A

# Check ingress/load balancer
echo ""
echo "LoadBalancer Services:"
kubectl get svc -A | grep LoadBalancer

echo ""
echo "========================================"
echo "🎯 ACCESS INFORMATION"
echo "========================================"

# Get Wazuh Dashboard URL
DASHBOARD_IP=$(kubectl get svc wazuh-dashboard -n siem -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
if [ "$DASHBOARD_IP" != "pending" ]; then
    echo "Wazuh Dashboard: https://$DASHBOARD_IP:5601"
    echo "Username: admin"
    echo "Password: SecretPassword"
else
    echo "Wazuh Dashboard: Waiting for LoadBalancer IP..."
fi

# Get Proxy LoadBalancer
PROXY_IP=$(kubectl get svc proxy-service -n honeynet -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
if [ "$PROXY_IP" != "pending" ]; then
    echo "Honeypot Proxy: http://$PROXY_IP (via ModSec WAF)"
else
    echo "Honeypot Proxy: Waiting for LoadBalancer IP..."
fi

echo ""
echo "========================================"
echo "🧪 TESTING COMMANDS"
echo "========================================"

cat << 'EOF'
# Test the deployment:

# 1. Check all pods are running
kubectl get pods -A

# 2. Test Wazuh agent connectivity
kubectl exec -n honeynet deployment/honeypot -- curl -f http://wazuh-manager.siem.svc.cluster.local:55000

# 3. Test honeypot accessibility
curl -k https://<proxy-ip>/  # Should be blocked by ModSec or reach honeypot

# 4. Check Fluent Bit logs
kubectl logs -n siem daemonset/fluent-bit

# 5. View Wazuh alerts
kubectl exec -n siem deployment/wazuh-manager -- tail -f /var/ossec/logs/alerts/alerts.json

# 6. Test threat central API
kubectl port-forward -n siem svc/threat-central 8080:8080 &
curl http://localhost:8080/health

EOF

print_success "🎉 Honeypot Lab deployment completed successfully!"
print_status "Use the testing commands above to verify functionality"
print_warning "Remember to update Docker image references with your registry URLs"