# k8s-postgrest-challenge

Implantação de uma API [PostgREST](https://postgrest.org/) integrada a um PostgreSQL em
um cluster Kubernetes local, com persistência de dados, configuração externalizada,
health checks, escala automática e (em breve) pipeline de CI/CD.

Feito como parte do desafio "Fundamentos de Kubernetes na Prática" do CloudOps Bootcamp
(S7 — Kubernetes), documentando cada nível progressivamente — não é só a entrega final,
é o histórico de como cada peça foi construída e por quê.

## Arquitetura

```
Você (curl)  →  Service (postgrest)  →  Deployment PostgREST (2+ réplicas)  →  Service (postgres)  →  Deployment PostgreSQL (1 réplica + PVC)
```

A API nunca se conecta ao banco por IP — ela usa o **nome do Service** (`postgres`) como
host na string de conexão, resolvido via DNS interno do cluster. Isso é o que permite o
Pod do banco ser recriado (perdendo IP) sem que a API perca a conexão. Ver a reflexão do
[Nível 4](docs/nivel-4-postgrest-integracao.md) para o detalhe completo.

## Ferramenta de cluster

**[kind](https://kind.sigs.k8s.io/)** (Kubernetes IN Docker), rodando dentro do WSL2
(Arch Linux) com integração ao Docker Desktop. Cluster criado com:

```bash
kind create cluster --name k8s-challenge
```

## Pré-requisitos

- Docker (com integração WSL2, se estiver no Windows)
- [`kind`](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)
- `curl` (pra testar a API)

## Como aplicar

```bash
git clone https://github.com/MeloJu/k8s-postgrest-challenge.git
cd k8s-postgrest-challenge
kind create cluster --name k8s-challenge   # pule se já tiver um cluster
kubectl apply -f k8s/
kubectl get pods -n desafio-k8s -w         # espere tudo ficar Running/Ready
```

Ver [`k8s/README.md`](k8s/README.md) para o que cada manifest faz e por que a numeração
não é cronológica.

### Bônus: HPA (Nível 7)

O HorizontalPodAutoscaler depende do `metrics-server`, que não vem instalado por padrão
no `kind`:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

(A flag `--kubelet-insecure-tls` é necessária porque o `kind` usa certificados
autoassinados nos kubelets — sem ela, o `metrics-server` sobe mas nunca reporta métricas.)

## Como testar

### Integração API ↔ banco

```bash
kubectl port-forward -n desafio-k8s svc/postgrest 3000:3000
```

Em outro terminal:

```bash
curl http://localhost:3000/todos
```

Deve retornar `[]` (tabela vazia) ou os registros já inseridos.

### Inserir e ler um dado

```bash
curl -X POST http://localhost:3000/todos \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"title": "minha primeira tarefa"}'

curl http://localhost:3000/todos
```

### Persistência (o coração do desafio)

```bash
kubectl delete pod -n desafio-k8s -l app=postgres
kubectl wait --for=condition=Ready pod -n desafio-k8s -l app=postgres --timeout=90s
curl http://localhost:3000/todos   # o dado inserido antes ainda deve estar lá
```

Se o `curl` logo após a recriação retornar um erro `57P01` (conexão encerrada), é
esperado — o pool de conexões do PostgREST ainda apontava pro Pod antigo. Tente de novo;
ele reconecta sozinho (ver [Nível 5](docs/nivel-5-persistencia.md) pra evidência real
disso acontecendo).

### Escalonamento automático (bônus)

```bash
kubectl run load-generator -n desafio-k8s --image=busybox:stable --restart=Never -- \
  /bin/sh -c "for i in 1 2 3 4; do (while true; do wget -q -O- http://postgrest:3000/todos > /dev/null; done) & done; wait"
kubectl get hpa -n desafio-k8s -w   # observe REPLICAS subindo
kubectl delete pod load-generator -n desafio-k8s
kubectl get hpa -n desafio-k8s -w   # observe REPLICAS voltando ao mínimo
```

## Limpeza

```bash
kubectl delete namespace desafio-k8s
kind delete cluster --name k8s-challenge   # se quiser remover o cluster inteiro também
```

## Documentação por nível

Cada nível do desafio tem seu próprio documento com o que foi feito, os comandos usados,
evidências e a resposta à pergunta de reflexão proposta:

| Nível | Documento | Peso na avaliação |
|---|---|---|
| 1 — Namespace e primeiro contato | [docs/nivel-1-namespace-pod.md](docs/nivel-1-namespace-pod.md) | parte de "Organização" (10%) |
| 2 — PostgreSQL com persistência | [docs/nivel-2-postgres-pvc.md](docs/nivel-2-postgres-pvc.md) | parte de "PVC e persistência" (30%) |
| 3 — Secret e ConfigMap | [docs/nivel-3-secret-configmap.md](docs/nivel-3-secret-configmap.md) | "ConfigMap + Secret" (15%) |
| 4 — API conectada ao banco | [docs/nivel-4-postgrest-integracao.md](docs/nivel-4-postgrest-integracao.md) | "Integração API↔banco" (25%) |
| 5 — Expor a API e provar persistência | [docs/nivel-5-persistencia.md](docs/nivel-5-persistencia.md) | "PVC e persistência" (30%) |
| 6 — Health checks e escala | [docs/nivel-6-probes-escala.md](docs/nivel-6-probes-escala.md) | "Health checks + limits" (10%) |
| 7 — Escalonamento automático (bônus) | [docs/nivel-7-hpa.md](docs/nivel-7-hpa.md) | bônus, fora do peso oficial |

Decisões que vão além do que o desafio pediu (imagens fixadas por digest, labels padrão,
estratégia de rollout) estão em [docs/hardening-producao.md](docs/hardening-producao.md).

## Evidências

Prints de cada etapa ficam em [`docs/evidencias/`](docs/evidencias/), referenciados a
partir do documento do nível correspondente. A visão geral do namespace com tudo rodando
junto (Pods, Services, Deployments, HPA, PVC, Secret, ConfigMap) está em
[`docs/evidencias/visao-geral-namespace.png`](docs/evidencias/visao-geral-namespace.png).

## Estrutura do repositório

```
k8s/                  # manifests numerados (ver k8s/README.md)
docs/
  nivel-N-*.md         # um documento por nível do desafio
  hardening-producao.md
  evidencias/          # prints referenciados pelos docs acima
tests/                 # testes automatizados (pytest) — em construção, ver CI/CD abaixo
.github/workflows/     # CI/CD — em construção
```

## CI/CD (em construção)

O plano é ter dois workflows do GitHub Actions:

- **`ci.yml`**: em PRs para `develop`/`main` — valida sintaxe dos manifests
  (kubeconform/kubeval), roda Checkov em `k8s/` e Semgrep em `tests/`. Soft-fail (reporta,
  não bloqueia).
- **`cd.yml`**: em push para `main` — sobe um cluster `kind` efêmero, aplica os
  manifests, espera tudo ficar `Ready`, e roda `pytest` (incluindo o teste automatizado
  de persistência). Hard-fail.

Este README será atualizado quando esses workflows estiverem prontos.

## GitFlow

Este repositório segue GitFlow: `main` (protegida, só recebe PR de `develop`),
`develop` (integração) e uma branch `feature/*` por nível, cada uma com seu próprio PR —
visível no [histórico de Pull Requests](https://github.com/MeloJu/k8s-postgrest-challenge/pulls?q=is%3Apr).
