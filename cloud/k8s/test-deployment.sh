#!/bin/bash

# Test script for honeypot lab deployment
# This script runs comprehensive tests to verify all components are working

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo "🧪 Testing Honeypot Lab Deployment..."
echo "====================================="

# Test 1: Check all pods are running
print_status "Checking pod status..."
TOTAL_PODS=$(kubectl get pods -A --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -A --field-selector=status.phase=Running --no-headers | wc -l)
PENDING_PODS=$(kubectl get pods -A --field-selector=status.phase=Pending --no-headers | wc -l)

if [ "$PENDING_PODS" -gt 0 ]; then
    print_warning "Some pods are still pending: $PENDING_PODS/$TOTAL_PODS"
    kubectl get pods -A --field-selector=status.phase=Pending
else
    print_success "All pods are running: $RUNNING_PODS/$TOTAL_PODS"
fi

# Test 2: Check node labels
print_status "Checking node labels..."
SIEM_NODES=$(kubectl get nodes -l role=siem --no-headers | wc -l)
HONEYPOT_NODES=$(kubectl get nodes -l role=honeypot --no-headers | wc -l)
PROXY_NODES=$(kubectl get nodes -l role=proxy --no-headers | wc -l)

if [ "$SIEM_NODES" -gt 0 ]; then
    print_success "SIEM nodes labeled: $SIEM_NODES"
else
    print_fail "No SIEM nodes found - run: kubectl label node <node> role=siem"
fi

if [ "$HONEYPOT_NODES" -gt 0 ]; then
    print_success "Honeypot nodes labeled: $HONEYPOT_NODES"
else
    print_fail "No honeypot nodes found - run: kubectl label node <node> role=honeypot"
fi

if [ "$PROXY_NODES" -gt 0 ]; then
    print_success "Proxy nodes labeled: $PROXY_NODES"
else
    print_fail "No proxy nodes found - run: kubectl label node <node> role=proxy"
fi

# Test 3: Check services
print_status "Checking services..."
kubectl get svc -A > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_success "Services are accessible"
else
    print_fail "Services check failed"
fi

# Test 4: Test inter-namespace connectivity
print_status "Testing inter-namespace connectivity..."

# Test honeypot to Wazuh Manager connectivity
kubectl run test-connectivity --image=busybox --rm -i --restart=Never --namespace=honeynet -- \
    wget -qO- --timeout=5 http://wazuh-manager.siem.svc.cluster.local:55000 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_success "Honeynet to SIEM connectivity: OK"
else
    print_fail "Honeynet to SIEM connectivity: FAILED"
    print_status "Check network policies and DNS resolution"
fi

# Test 5: Check ConfigMaps
print_status "Checking ConfigMaps..."
CONFIGMAPS=$(kubectl get configmaps -A --no-headers | wc -l)
if [ "$CONFIGMAPS" -gt 0 ]; then
    print_success "ConfigMaps created: $CONFIGMAPS"
else
    print_fail "No ConfigMaps found"
fi

# Test 6: Check Secrets
print_status "Checking Secrets..."
SECRETS=$(kubectl get secrets -A --no-headers | grep -v "default-token" | wc -l)
if [ "$SECRETS" -gt 0 ]; then
    print_success "Secrets created: $SECRETS"
else
    print_fail "No Secrets found"
fi

# Test 7: Test honeypot accessibility
print_status "Testing honeypot accessibility..."
PROXY_SVC=$(kubectl get svc proxy-service -n honeynet -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$PROXY_SVC" ] && [ "$PROXY_SVC" != "pending" ]; then
    # Test HTTP connectivity
    curl -k --max-time 10 "http://$PROXY_SVC" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "HTTP proxy accessible: http://$PROXY_SVC"
    else
        print_warning "HTTP proxy not accessible (may be expected if ModSec blocks)"
    fi

    # Test HTTPS connectivity
    curl -k --max-time 10 "https://$PROXY_SVC" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "HTTPS proxy accessible: https://$PROXY_SVC"
    else
        print_warning "HTTPS proxy not accessible"
    fi
else
    print_warning "Proxy LoadBalancer not ready yet - check: kubectl get svc -n honeynet"
fi

# Test 8: Check Wazuh Dashboard
print_status "Checking Wazuh Dashboard..."
DASHBOARD_SVC=$(kubectl get svc wazuh-dashboard -n siem -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$DASHBOARD_SVC" ] && [ "$DASHBOARD_SVC" != "pending" ]; then
    # Test dashboard connectivity
    curl -k --max-time 10 "https://$DASHBOARD_SVC:5601" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "Wazuh Dashboard accessible: https://$DASHBOARD_SVC:5601"
        echo "    Username: admin"
        echo "    Password: SecretPassword"
    else
        print_warning "Wazuh Dashboard not accessible yet - still initializing"
    fi
else
    print_warning "Dashboard LoadBalancer not ready yet - check: kubectl get svc -n siem"
fi

# Test 9: Check Fluent Bit logs
print_status "Checking Fluent Bit operation..."
FLUENT_PODS=$(kubectl get pods -n siem -l app=fluent-bit --no-headers | wc -l)
if [ "$FLUENT_PODS" -gt 0 ]; then
    # Check if Fluent Bit is processing logs
    LOGS=$(kubectl logs -n siem daemonset/fluent-bit --tail=10 2>/dev/null | wc -l)
    if [ "$LOGS" -gt 0 ]; then
        print_success "Fluent Bit is processing logs"
    else
        print_warning "Fluent Bit running but no recent logs"
    fi
else
    print_fail "Fluent Bit pods not found"
fi

# Test 10: Check Wazuh Manager logs
print_status "Checking Wazuh Manager operation..."
WAZUH_LOGS=$(kubectl logs -n siem deployment/wazuh-manager --tail=10 2>/dev/null | grep -c "INFO" || echo "0")
if [ "$WAZUH_LOGS" -gt 0 ]; then
    print_success "Wazuh Manager is operational"
else
    print_warning "Wazuh Manager may still be initializing"
fi

echo ""
echo "========================================"
echo "📊 TEST SUMMARY"
echo "========================================"

echo ""
echo "🎯 Next Steps:"
echo "1. If LoadBalancers show 'pending', wait for AWS to provision them"
echo "2. Update Docker image references in deployments with your registry"
echo "3. Generate proper SSL certificates for production use"
echo "4. Test actual attack scenarios against the honeypot"
echo "5. Monitor logs in Wazuh Dashboard for security events"

echo ""
echo "🔍 Useful Commands:"
echo "# View all pods: kubectl get pods -A"
echo "# Check logs: kubectl logs -n <namespace> <pod-name>"
echo "# Port forward: kubectl port-forward -n siem svc/wazuh-dashboard 5601:5601"
echo "# Debug networking: kubectl exec -it <pod> -- nslookup wazuh-manager.siem.svc.cluster.local"

print_success "Testing completed! Check results above."