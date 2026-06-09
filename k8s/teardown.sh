#!/bin/bash
# Tear down the current architecture before deploying the next one.
# The logging stack (Loki/Grafana) is left running.
set -e

echo "=== Deleting all app deployments, services, PVCs ==="
kubectl delete deploy --all --ignore-not-found
kubectl delete svc --all --ignore-not-found
kubectl delete pvc --all --ignore-not-found
kubectl delete configmap --field-selector metadata.name!=kube-root-ca.crt --ignore-not-found

echo "=== Re-deploying logging stack ==="
kubectl apply -f "$(dirname "$0")/logging-stack.yaml"

echo "=== Clean. Ready for next architecture. ==="
kubectl get all
