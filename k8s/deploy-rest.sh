#!/bin/bash
set -e
cd "$(dirname "$0")/.."

echo "=== Creating ConfigMaps for REST Shiny scripts ==="
SHINY=Thesis-Project-Final-RESTAPI/shiny_services

kubectl create configmap rest-nginx-config --from-file=nginx.conf=$SHINY/nginx.conf --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-calc \
  --from-file=shiny_front.r=$SHINY/calculator/shiny_front.r \
  --from-file=shiny_back.r=$SHINY/calculator/shiny_back.r \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-analytics \
  --from-file=shiny_front_analytics.r=$SHINY/visual_analytics/shiny_front_analytics.r \
  --from-file=shiny_back_analytics.r=$SHINY/visual_analytics/shiny_back_analytics.r \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-adv-analytics \
  --from-file=shiny_front_analytics_advanced.r=$SHINY/visual_analytics/shiny_front_analytics_advanced.r \
  --from-file=shiny_back_analytics_advanced.r=$SHINY/visual_analytics/shiny_back_analytics_advanced.r \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-csv \
  --from-file=shiny_front_csv.r=$SHINY/data_exchange/shiny_front_csv.r \
  --from-file=shiny_back_csv.r=$SHINY/data_exchange/shiny_back_csv.r \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-csv-adv \
  --from-file=shiny_front_csv_advanced.r=$SHINY/data_exchange/shiny_front_csv_advanced.r \
  --from-file=shiny_back_csv_advanced.r=$SHINY/data_exchange/shiny_back_csv_advanced.r \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-mc \
  --from-file=shiny_front_mc.r=$SHINY/monte_carlo/shiny_front_mc.r \
  --from-file=shiny_back_mc.r=$SHINY/monte_carlo/shiny_back_mc.r \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-map \
  --from-file=shiny_front_map.r=$SHINY/map/shiny_front_map.r \
  --from-file=shiny_back_map.r=$SHINY/map/shiny_back_map.r \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap rest-scripts-ml \
  --from-file=shiny_front_ml.r=$SHINY/machine_learning/shiny_front_ml.r \
  --from-file=shiny_back_ml.r=$SHINY/machine_learning/shiny_back_ml.r \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Deploying REST architecture ==="
kubectl apply -f k8s/rest-deployment.yaml

echo "=== Done. Pods: ==="
kubectl get pods
