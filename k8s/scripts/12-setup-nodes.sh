#!/bin/bash

# Get worker nodes (exclude control-plane)
WORKERS=($(kubectl get nodes --no-headers \
  | grep -v control-plane \
  | awk '{print $1}'))

echo "Found worker nodes: ${WORKERS[@]}"

# Label and taint the first worker for database workloads
DB_NODE=${WORKERS[0]}
echo "Configuring node: $DB_NODE"

kubectl label node $DB_NODE type=high-memory --overwrite
kubectl taint nodes $DB_NODE database-only=true:NoSchedule --overwrite

echo "✅ Node $DB_NODE labeled and tainted"
echo ""

# Verify
echo "── Node Labels ──────────────────────────────"
kubectl get node $DB_NODE --show-labels

echo ""
echo "── Node Taints ──────────────────────────────"
kubectl describe node $DB_NODE | grep Taints