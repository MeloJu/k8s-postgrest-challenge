# Nível 7 — Escalonamento automático (bônus)

## Objetivo

Configurar um HorizontalPodAutoscaler (HPA) para o PostgREST, escalando conforme o uso
de CPU, e observar o cluster criar e remover Pods automaticamente sob carga.

## O que foi feito

### 1. metrics-server

O HPA depende do `metrics-server` pra saber o uso real de CPU dos Pods — algo que o
`kind` não instala por padrão.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Isso não entra em `k8s/` porque é infraestrutura do cluster, não parte da aplicação do
desafio (não seria reaplicado num cluster já existente).

O `metrics-server` por padrão tenta validar o certificado TLS do kubelet de cada nó — e o
`kind` usa certificados autoassinados que não validam nessa cadeia. Sem esse ajuste, o
`metrics-server` sobe mas nunca reporta métricas:

```bash
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

Confirmação:
```bash
kubectl top pods -n desafio-k8s
```

### 2. HorizontalPodAutoscaler ([`k8s/08-postgrest-hpa.yaml`](../k8s/08-postgrest-hpa.yaml))

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: postgrest
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
```

- `averageUtilization: 50` é relativo ao `requests.cpu` do Nível 6 (100m) — o HPA tenta
  manter a média de uso em torno de 50m por Pod; acima disso, escala pra cima.
- `behavior.scaleDown.stabilizationWindowSeconds: 30`: o padrão do Kubernetes é **5
  minutos** de estabilização antes de reduzir réplicas (evita "flapping" — subir e descer
  repetidamente por picos curtos de carga). Reduzi pra 30s **só pra viabilizar demonstrar
  o scale-down num tempo razoável neste README**; em produção, o padrão de 5 minutos é a
  escolha mais segura.

```bash
kubectl apply -f k8s/08-postgrest-hpa.yaml
kubectl get hpa -n desafio-k8s
```

### 3. Gerando carga

```bash
kubectl run load-generator -n desafio-k8s --image=busybox:stable --restart=Never -- \
  /bin/sh -c "for i in 1 2 3 4; do (while true; do wget -q -O- http://postgrest:3000/todos > /dev/null; done) & done; wait"
```

Um Pod descartável, rodando **dentro do cluster**, com 4 loops paralelos batendo direto
no Service `postgrest` pelo nome (mesmo mecanismo de DNS interno do Nível 4). Rodar de
dentro do cluster evita depender de `port-forward` (que roda na máquina host, fora do
cluster) pra sustentar uma carga contínua.

## Evidências

Sob carga — CPU em 200% do alvo, escalou até o teto configurado (6 réplicas):

![HPA em 200%/50%, 6 réplicas rodando, uso de CPU real por Pod](evidencias/nivel-7-hpa-scale-up.png)

Depois de remover a carga — CPU volta a 2%, réplicas voltam ao mínimo (2):

![HPA em 2%/50%, de volta a 2 réplicas](evidencias/nivel-7-hpa-scale-down.png)

## Conclusão

O HPA fechou o ciclo de elasticidade que o Nível 6 preparou: como o PostgREST é sem
estado e o Service já distribui carga entre quantas réplicas existirem, adicionar ou
remover Pods automaticamente é seguro — o mesmo raciocínio da reflexão do Nível 6, agora
automatizado por um controlador do próprio Kubernetes reagindo a métricas reais, sem
qualquer intervenção manual.
