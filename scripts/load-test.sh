#!/usr/bin/env bash
# Gera carga na API e acompanha o HorizontalPodAutoscaler reagindo.
#
#   ./scripts/load-test.sh [duracao_em_segundos]
#
# A carga roda dentro do cluster, acessando o Service pelo nome — não depende de
# port-forward, que roda na máquina host e não sustenta carga contínua de forma confiável.
set -euo pipefail

NAMESPACE="desafio-k8s"
DURATION="${1:-120}"
WORKERS=4

cleanup() {
  echo
  echo "==> Removendo o gerador de carga"
  kubectl delete pod load-generator -n "$NAMESPACE" --ignore-not-found --wait=false
}
trap cleanup EXIT

if ! kubectl get hpa postgrest -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "HPA não encontrado. Rode ./scripts/setup.sh antes." >&2
  exit 1
fi

echo "==> Estado inicial"
kubectl get hpa postgrest -n "$NAMESPACE"

kubectl delete pod load-generator -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1

echo
echo "==> Subindo o gerador de carga (${WORKERS} processos por ${DURATION}s)"
kubectl run load-generator -n "$NAMESPACE" --image=busybox:stable --restart=Never -- \
  /bin/sh -c "for i in \$(seq 1 ${WORKERS}); do (while true; do wget -q -O- http://postgrest:3000/todos > /dev/null; done) & done; wait"

kubectl wait --for=condition=Ready pod/load-generator -n "$NAMESPACE" --timeout=60s

echo
echo "==> Acompanhando o HPA (Ctrl+C para sair antes do fim)"
END=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END" ]; do
  kubectl get hpa postgrest -n "$NAMESPACE" --no-headers
  sleep 10
done

cleanup
trap - EXIT

echo
echo "==> Carga removida. Acompanhando a redução de réplicas"
for _ in $(seq 1 12); do
  kubectl get hpa postgrest -n "$NAMESPACE" --no-headers
  sleep 10
done
