# Manifests

> **A numeração destes arquivos é ordem de aplicação, não ordem dos níveis do desafio.**
> `01-postgres-secret.yaml` vem antes de `04-postgres-deployment.yaml` porque o Deployment
> consome o Secret — não porque um seja de um nível anterior. A coluna "Documentação" na
> tabela abaixo liga cada manifest ao documento correspondente.

`kubectl apply -f k8s/` funciona porque o `kubectl` processa os arquivos em ordem
alfabética dentro da pasta, e a numeração segue a dependência lógica: configuração antes
de quem a consome, banco antes da API.

| Arquivo | Recurso | Documentação |
|---|---|---|
| `00-namespace.yaml` | Namespace `desafio-k8s` | [Namespace](../docs/nivel-1-namespace-pod.md) |
| `01-postgres-secret.yaml` | Secret: senhas e configuração do PostgREST | [Credenciais](../docs/nivel-3-secret-configmap.md) |
| `02-postgres-configmap.yaml` | ConfigMap: configuração e script de inicialização | [Credenciais](../docs/nivel-3-secret-configmap.md) |
| `03-postgres-pvc.yaml` | PersistentVolumeClaim do banco | [Armazenamento](../docs/nivel-2-postgres-pvc.md) |
| `04-postgres-deployment.yaml` | Deployment do PostgreSQL | [Armazenamento](../docs/nivel-2-postgres-pvc.md) |
| `05-postgres-service.yaml` | Service ClusterIP do banco | [Armazenamento](../docs/nivel-2-postgres-pvc.md) |
| `06-postgrest-deployment.yaml` | Deployment do PostgREST | [API](../docs/nivel-4-postgrest-integracao.md) |
| `07-postgrest-service.yaml` | Service ClusterIP da API | [Exposição](../docs/nivel-5-persistencia.md) |
| `08-postgrest-hpa.yaml` | HorizontalPodAutoscaler da API | [Escala automática](../docs/nivel-7-hpa.md) |
| `09-network-policies.yaml` | NetworkPolicies: default deny + liberações mínimas | [Segurança](../docs/hardening-producao.md#segmentação-de-rede) |

Decisões transversais (imagens por digest, contexto de segurança dos containers,
estratégia de rollout) estão em
[`docs/hardening-producao.md`](../docs/hardening-producao.md).

## Aplicar

```bash
kubectl apply -f k8s/
```

Um volume novo é inicializado pelo script `init.sh` do ConfigMap, que cria a tabela, os
papéis de acesso e os registros de exemplo. Nenhum passo manual é necessário.

## Remover

```bash
kubectl delete namespace desafio-k8s
```

Remove todos os recursos do namespace, incluindo o HPA. O `metrics-server` vive em
`kube-system` e não é afetado — ver [escala automática](../docs/nivel-7-hpa.md).
