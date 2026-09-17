# Manifests

Arquivos numerados na ordem em que devem ser aplicados — `kubectl apply -f k8s/` funciona
porque o `kubectl` processa os arquivos em ordem alfabética/numérica dentro da pasta.

A numeração segue a ordem lógica de dependência (config antes de quem consome, banco
antes da API), **não** a ordem cronológica em que foram criados durante o desafio — por
isso `01`/`02` (Secret/ConfigMap) só passaram a existir depois do PVC (`03`), quando o
[Nível 3](../docs/nivel-3-secret-configmap.md) migrou as credenciais que já estavam
hardcoded no Deployment desde o [Nível 2](../docs/nivel-2-postgres-pvc.md).

| Arquivo | Recurso | Nível |
|---|---|---|
| `00-namespace.yaml` | Namespace `desafio-k8s` | [1](../docs/nivel-1-namespace-pod.md) |
| `01-postgres-secret.yaml` | Secret com credenciais do Postgres | [3](../docs/nivel-3-secret-configmap.md) |
| `02-postgres-configmap.yaml` | ConfigMap com config não sensível | [3](../docs/nivel-3-secret-configmap.md) |
| `03-postgres-pvc.yaml` | PersistentVolumeClaim do Postgres | [2](../docs/nivel-2-postgres-pvc.md) |
| `04-postgres-deployment.yaml` | Deployment do PostgreSQL | [2](../docs/nivel-2-postgres-pvc.md) |
| `05-postgres-service.yaml` | Service (ClusterIP) do Postgres | [2](../docs/nivel-2-postgres-pvc.md) |
| `06-postgrest-deployment.yaml` | Deployment do PostgREST | [4](../docs/nivel-4-postgrest-integracao.md) / [6](../docs/nivel-6-probes-escala.md) |
| `07-postgrest-service.yaml` | Service (ClusterIP) da API | [5](../docs/nivel-5-persistencia.md) |
| `08-postgrest-hpa.yaml` | HorizontalPodAutoscaler da API | [7](../docs/nivel-7-hpa.md) (bônus) |

Decisões que não pertencem a um nível específico (imagens fixadas, labels padrão,
estratégia de rollout do Postgres) estão em [`docs/hardening-producao.md`](../docs/hardening-producao.md).

## Aplicar tudo

```bash
kubectl apply -f k8s/
```

## Derrubar tudo

```bash
kubectl delete namespace desafio-k8s
```

Deletar o Namespace remove todos os recursos dentro dele de uma vez, incluindo o
`HorizontalPodAutoscaler`. A única coisa que fica de fora é o `metrics-server`, que vive
em `kube-system` (ver [Nível 7](../docs/nivel-7-hpa.md) para instalá-lo de novo).
