#!/usr/bin/env bash
# Sobe o ambiente inteiro: cluster local, plataforma e aplicação.
#
#   ./scripts/setup.sh
#
# Idempotente: se o cluster já existir, reaproveita.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-k8s-challenge}"
NAMESPACE="desafio-k8s"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "==> Cluster '${CLUSTER_NAME}' já existe, reaproveitando"
else
  echo "==> Criando cluster kind '${CLUSTER_NAME}'"
  kind create cluster --name "$CLUSTER_NAME"
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

"${REPO_ROOT}/scripts/install-metrics-server.sh"

echo "==> Aplicando os manifests da aplicação"
kubectl apply -f "${REPO_ROOT}/k8s/"

echo "==> Aguardando os Pods ficarem prontos"
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=180s

echo
echo "Ambiente pronto."
kubectl get pods,svc,hpa -n "$NAMESPACE"
echo
echo "Para acessar a API:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/postgrest 3000:3000"
echo "  curl http://localhost:3000/todos"
echo
echo "Para ver o autoscaling sob carga:"
echo "  ./scripts/load-test.sh"
