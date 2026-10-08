#!/usr/bin/env bash
# Plain-manifest install (the Helm chart in ../helm is the primary path; this shows the raw objects).
set -euo pipefail
cd "$(dirname "$0")"
kubectl apply -f 00-namespace.yaml -f 01-configmap.yaml
if ! kubectl -n incidentdesk get secret incidentdesk-db >/dev/null 2>&1; then
  echo "creating Secret incidentdesk-db with a random password (never stored in Git)"
  kubectl -n incidentdesk create secret generic incidentdesk-db --from-literal=password="$(openssl rand -hex 16)"
fi
kubectl apply -f 03-postgres.yaml -f 04-backend.yaml -f 05-frontend.yaml -f 06-ingress.yaml -f 07-hpa.yaml
kubectl -n incidentdesk rollout status statefulset/incidentdesk-postgres --timeout=180s
kubectl -n incidentdesk rollout status deploy/incidentdesk-backend --timeout=240s
kubectl -n incidentdesk rollout status deploy/incidentdesk-frontend --timeout=120s
