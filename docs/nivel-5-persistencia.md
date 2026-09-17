# Nível 5 — Expor a API e provar a persistência

Este é o nível de maior peso na avaliação (30%) — é onde todas as peças dos níveis
anteriores (PVC, Secret, ConfigMap, Service, Deployment) precisam ter funcionado juntas
de verdade.

## Objetivo

Expor a API para acesso externo, inserir um dado via POST, deletar o Pod do PostgreSQL,
esperar o cluster recriá-lo, e confirmar via GET que o dado sobreviveu.

## O que foi feito

### 1. Service da API ([`k8s/07-postgrest-service.yaml`](../k8s/07-postgrest-service.yaml))

```bash
kubectl apply -f k8s/07-postgrest-service.yaml
```

Um `ClusterIP` como o do Postgres. A exposição "pra fora do cluster" é feita com
`kubectl port-forward`, a técnica que o próprio enunciado do desafio agrupa junto de
Service para este fim — ele cria um túnel entre uma porta da sua máquina e a porta do
Service dentro do cluster.

### 2. Antes: inserir e ler um dado

```bash
kubectl port-forward -n desafio-k8s svc/postgrest 3000:3000
```

Em outro terminal:

```bash
curl -X POST http://localhost:3000/todos \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"title": "sobrevivi a recriacao do pod"}'

curl http://localhost:3000/todos
```

O header `Prefer: return=representation` faz o PostgREST devolver a linha inserida na
resposta do POST (sem ele, um POST bem-sucedido retorna `201` sem corpo).

![POST inserindo o dado e GET confirmando, antes de deletar o Pod](evidencias/nivel-5-persistencia-antes.png)

### 3. Deletar o Pod do Postgres e esperar recriação

```bash
kubectl get pods -n desafio-k8s -l app=postgres
kubectl delete pod -n desafio-k8s -l app=postgres
kubectl wait --for=condition=Ready pod -n desafio-k8s -l app=postgres --timeout=90s
kubectl get pods -n desafio-k8s -l app=postgres
```

Usei `-l app=postgres` (seletor por label) em vez do nome exato do Pod — assim o comando
funciona sem eu precisar descobrir o sufixo aleatório toda vez. O Pod recriado teve um
sufixo diferente do original (`-ctw7j` → `-95vhz`), confirmando que é um Pod **novo**, não
o mesmo reaproveitado.

### 4. Depois: confirmar que o dado sobreviveu

```bash
curl http://localhost:3000/todos
```

![Delete do Pod, espera pela recriação, e confirmação via GET](evidencias/nivel-5-persistencia-depois.png)

**Detalhe real que apareceu na captura**: a primeira tentativa de GET logo após o Pod
novo ficar `Ready` retornou um erro do Postgres (`57P01 — terminating connection due to
administrator command`). Isso acontece porque o PostgREST mantém um **pool de conexões**
com o banco, e a conexão que estava no pool ainda apontava para o Pod antigo — que foi
morto junto com o Pod. Na tentativa seguinte, o PostgREST já havia descartado a conexão
morta e reconectado no Pod novo (pelo mesmo nome de Service, `postgres`), e o dado
apareceu normalmente. Não escondi esse erro da evidência porque ele é real e didático:
mostra o pool de conexões se recuperando sozinho, sem intervenção manual.

## Reflexão

**Quantos componentes tiveram que funcionar em conjunto para esse dado sobreviver? O que
isso mostra sobre como o Kubernetes coordena as peças?**

Pelo menos seis, e a falha de qualquer um deles quebraria a prova:

1. **PVC** (`postgres-pvc`) — sem ele, os dados estariam no `emptyDir` do Pod e teriam
   sumido junto com o Pod deletado (Nível 2).
2. **Deployment do Postgres** — é quem detecta que o Pod sumiu e cria um substituto
   automaticamente (Nível 1: um Pod avulso não teria voltado sozinho).
3. **Secret** — fornece as mesmas credenciais para o Pod novo; se elas fossem diferentes
   a cada recriação, a API perderia acesso ao banco (Nível 3).
4. **Service do Postgres** (`postgres`) — mantém o endereço de rede estável para a API
   encontrar o Pod novo, mesmo com IP diferente (Nível 4).
5. **Deployment do PostgREST** — precisa se manter no ar e ter um mecanismo de
   reconexão (o pool) capaz de se recuperar quando a conexão de banco morre no meio do
   caminho.
6. **Service do PostgREST** (`postgrest`) — o ponto de acesso estável que permitiu
   testar a API antes e depois sem mudar nada no lado do cliente.

O que isso mostra: o Kubernetes não garante persistência ou disponibilidade através de
**um** recurso mágico — é a **composição** de vários controladores independentes, cada
um responsável por reconciliar um pedaço pequeno do estado desejado (o ReplicaSet cuida
de "quantos Pods existem", o PVC cuida de "onde os dados vivem", o Service cuida de "como
encontrar o Pod certo"), que produz o comportamento de auto-recuperação como efeito
colateral da soma das partes. Nenhum desses controladores sabe dos outros — o Deployment
do Postgres não sabe que existe uma API dependendo dele; ele só sabe manter o número de
réplicas correto. É a composição desses loops de reconciliação independentes, cada um
simples isoladamente, que sustenta o sistema como um todo.
