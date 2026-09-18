#!/usr/bin/env bash
# Instala o metrics-server, dependência do HorizontalPodAutoscaler.
#
# É componente de plataforma, não da aplicação: em clusters gerenciados (EKS, GKE, AKS)
# normalmente já vem instalado, e por isso não está em k8s/. Este script é a fonte única
# do procedimento, usada tanto pelo setup local quanto pelo pipeline de CD.
set -euo pipefail

METRICS_SERVER_VERSION="v0.9.0"

echo "==> Instalando metrics-server ${METRICS_SERVER_VERSION}"
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

# O kind usa certificados autoassinados nos kubelets; sem esta flag o metrics-server
# sobe mas nunca consegue coletar métricas. Em cluster gerenciado o patch é desnecessário.
echo "==> Ajustando validação de TLS do kubelet (necessário no kind)"
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

echo "==> Aguardando o metrics-server ficar disponível"
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s

echo "==> Aguardando as primeiras métricas serem coletadas"
for _ in $(seq 1 30); do
  if kubectl top nodes >/dev/null 2>&1; then
    echo "metrics-server reportando métricas."
    exit 0
  fi
  sleep 5
done

echo "metrics-server instalado, mas ainda não reportou métricas." >&2
exit 1
