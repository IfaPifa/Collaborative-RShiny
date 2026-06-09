#!/bin/bash
set -e
cd "$(dirname "$0")/.."

echo "=== Creating ConfigMaps for Monolithic Shiny apps ==="
APPS=whole_apps

kubectl create configmap mono-nginx-config --from-file=nginx.conf=$APPS/nginx.conf --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-calculator --from-file=app.r=$APPS/calculator/app.r --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-analytics --from-file=app.r=$APPS/analytics/app.r --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-analytics-advanced --from-file=app.r=$APPS/analytics_advanced/app.r --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-csv --from-file=app.r=$APPS/data_exchange/app.r --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-anomaly --from-file=app.r=$APPS/anomaly_detector/app.r --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-map --from-file=app.r=$APPS/map/app.r --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-montecarlo --from-file=app.r=$APPS/montecarlo/app.r --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap mono-app-ml --from-file=app.r=$APPS/ml_trainer/app.r --dry-run=client -o yaml | kubectl apply -f -

echo "=== Deploying Monolithic architecture ==="
kubectl apply -f k8s/monolithic-deployment.yaml

echo "=== Done. Pods: ==="
kubectl get pods
