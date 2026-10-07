#!/usr/bin/env bash
# Prints one timestamped snapshot of the HPA, the pods and their CPU every $1 seconds (default 15).
while true; do
  echo "----- $(date +%T)"
  kubectl get hpa hpa-demo --no-headers 2>&1
  kubectl top pods -l app=hpa-demo --no-headers 2>&1 | sort
  sleep "${1:-15}"
done
