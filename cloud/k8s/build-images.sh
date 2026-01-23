#!/bin/bash

# Build and push Docker images for honeypot lab
# This script builds all custom container images and pushes them to a registry

set -e

# Configuration
REGISTRY="${REGISTRY:-your-registry.com/honeylab}"
TAG="${TAG:-latest}"

echo "Building and pushing Docker images to $REGISTRY..."

# Build honeypot image
echo "Building honeypot image..."
if [ -d "./honeypots-qeeqbox" ]; then
    cd honeypots-qeeqbox
    docker build -t "$REGISTRY/honeypot:$TAG" .
    docker push "$REGISTRY/honeypot:$TAG"
    cd ..
    echo "✅ Honeypot image built and pushed"
else
    echo "⚠️  honeypots-qeeqbox directory not found - using justsky/honeypots:latest from Docker Hub"
    docker pull justsky/honeypots:latest
    docker tag justsky/honeypots:latest "$REGISTRY/honeypot:$TAG"
    docker push "$REGISTRY/honeypot:$TAG"
    echo "✅ Honeypot image pulled from Docker Hub and pushed"
fi

# Build modsec-proxy image
echo "Building modsec-proxy image..."
if [ -d "./modsec-proxy" ]; then
    cd modsec-proxy
    docker build -t "$REGISTRY/modsec-proxy:$TAG" .
    docker push "$REGISTRY/modsec-proxy:$TAG"
    cd ..
    echo "✅ ModSec proxy image built and pushed"
else
    echo "⚠️  modsec-proxy directory not found - create Dockerfile and nginx config"
fi

# Build threat-central image
echo "Building threat-central image..."
if [ -d "./threat-central" ]; then
    cd threat-central
    docker build -t "$REGISTRY/threat-central:$TAG" .
    docker push "$REGISTRY/threat-central:$TAG"
    cd ..
    echo "✅ Threat central image built and pushed"
else
    echo "⚠️  threat-central directory not found - create Dockerfile and application code"
fi

echo ""
echo "🎉 All images built and pushed successfully!"
echo ""
echo "To use these images in Kubernetes, update your deployments:"
echo "  - honeypot: $REGISTRY/honeypot:$TAG"
echo "  - modsec-proxy: $REGISTRY/modsec-proxy:$TAG"
echo "  - threat-central: $REGISTRY/threat-central:$TAG"
echo ""
echo "Set the registry environment variable:"
echo "  export REGISTRY=your-registry.com/honeylab"
echo "  export TAG=v1.0.0"