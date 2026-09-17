# Nível 2 — Banco de dados com persistência

## Objetivo

Implantar o PostgreSQL com armazenamento que sobrevive à recriação do Pod, e um Service
para que outros recursos consigam encontrá-lo pelo nome.

## O que foi feito

### 1. PersistentVolumeClaim ([`k8s/03-postgres-pvc.yaml`](../k8s/03-postgres-pvc.yaml))

Um PVC é um pedido de armazenamento: você declara quanto espaço quer (`256Mi`) e como
quer acessá-lo (`ReadWriteOnce` — um único nó por vez, padrão pra disco de bloco). O
`storageClassName` foi deixado de fora de propósito: o `kind` já registra uma
StorageClass `standard` marcada como padrão (via `rancher.io/local-path`), então o PVC
usa essa automaticamente.

```bash
kubectl apply -f k8s/03-postgres-pvc.yaml
kubectl get pvc -n desafio-k8s
```

`STATUS` precisa ficar `Bound` (não `Pending`) — significa que o PVC foi vinculado a um
volume real.

### 2. Deployment do Postgres ([`k8s/04-postgres-deployment.yaml`](../k8s/04-postgres-deployment.yaml))

- `replicas: 1` é proposital — um PVC `ReadWriteOnce` só pode ser montado por um Pod de
  cada vez, então esse Deployment nunca deve ser escalado (volta no Nível 6).
- `env.PGDATA=/var/lib/postgresql/data/pgdata`: aponta o Postgres pra uma subpasta dentro
  do volume montado. É a prática recomendada pela própria imagem oficial — evita erro de
  inicialização caso o diretório raiz do volume não esteja 100% vazio.
- `volumes` (nível Pod) declara **o quê** montar (o PVC `postgres-pvc`);
  `volumeMounts` (nível container) diz **onde** montar (`/var/lib/postgresql/data`).
- **Credenciais hardcoded (`POSTGRES_USER`/`POSTGRES_PASSWORD`) direto no YAML — de
  propósito.** É a prática ruim que o Nível 3 vai corrigir movendo pra um Secret.

```bash
kubectl apply -f k8s/04-postgres-deployment.yaml
kubectl get pods -n desafio-k8s -w
```

### 3. Service ([`k8s/05-postgres-service.yaml`](../k8s/05-postgres-service.yaml))

`ClusterIP` (o padrão, sem precisar declarar `type`) — só acessível de dentro do
cluster, que é exatamente o que se quer: só a API (Nível 4) precisa falar com o banco,
nunca alguém de fora. O nome do Service (`postgres`) é o que vira endereço DNS interno
usado no Nível 4.

```bash
kubectl apply -f k8s/05-postgres-service.yaml
kubectl get svc -n desafio-k8s
```

### 4. Conferência

```bash
kubectl exec -it deployment/postgres -n desafio-k8s -- psql -U desafio_user -d desafio_db -c "SELECT version();"
```

`kubectl exec` roda um comando dentro do container já existente (equivalente ao
`docker exec`). Apontar pra `deployment/postgres` em vez do nome exato do Pod evita
precisar descobrir o sufixo aleatório gerado pelo ReplicaSet.

## Evidências

![PVC, Deployment, Service e conferência via psql](evidencias/nivel-2-postgres-pvc.png)

## Reflexão

**Qual a diferença entre montar um PVC e um `emptyDir`? O que aconteceria com os dados
em cada caso ao deletar o Pod?**

Um `emptyDir` é um volume criado junto com o Pod, vivendo no mesmo nó — seu ciclo de
vida está **atrelado ao Pod**: quando o Pod é removido (por qualquer motivo: deleção
manual, recriação pelo Deployment, realocação de nó), o `emptyDir` e tudo que estava
nele desaparece junto. Ele serve pra dados descartáveis ou cache compartilhado entre
containers do mesmo Pod, nunca pra dados que precisam sobreviver.

Um PVC tem ciclo de vida **independente do Pod**. Ele existe como um objeto próprio no
cluster, vinculado a um volume real (aqui, um diretório gerenciado pelo
`local-path-provisioner` do kind). Quando o Pod que o usa é deletado e o Deployment cria
um Pod substituto, o novo Pod monta o **mesmo** PVC — e portanto o **mesmo** volume com
os mesmos dados. É essa independência que torna possível a prova de persistência do
Nível 5: o dado sobrevive porque ele nunca esteve "dentro" do Pod, estava num volume que
o Pod apenas monta temporariamente.
