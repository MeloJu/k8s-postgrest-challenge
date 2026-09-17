# 6 — Health checks, limites e escala

## Probes

Ambos os Deployments declaram liveness e readiness, respondendo a perguntas diferentes:

| | Pergunta | Ação em caso de falha |
|---|---|---|
| **Liveness** | o processo travou? | mata e reinicia o container |
| **Readiness** | pode receber tráfego agora? | remove o Pod dos endpoints do Service |

Na API ([`k8s/06-postgrest-deployment.yaml`](../k8s/06-postgrest-deployment.yaml)) os
caminhos são propositalmente diferentes: liveness usa `GET /`, que depende apenas do
schema em memória; readiness usa `GET /todos`, que exige ida ao banco.

Se o Postgres cair temporariamente, readiness falha — correto, a API não deve receber
tráfego que não consegue atender — mas liveness continua passando, evitando o reinício de
um processo saudável por um problema externo a ele. Usar o mesmo endpoint nos dois
transformaria uma indisponibilidade do banco em um `CrashLoopBackOff` da API.

No banco ([`k8s/04-postgres-deployment.yaml`](../k8s/04-postgres-deployment.yaml)) as duas
probes usam `pg_isready`, a ferramenta oficial do Postgres: confirma que o servidor aceita
conexões, e não apenas que o processo existe.

## Requests e limits

```yaml
resources:
  requests: { cpu: 100m, memory: 64Mi }
  limits:   { cpu: 250m, memory: 128Mi }
```

`requests` é o que o scheduler reserva e usa para decidir em qual nó o Pod cabe; `limits`
é o teto. Estourar o limite de memória mata o container (`OOMKilled`); estourar o de CPU
apenas causa throttling. Sem `requests`, o Pod entra na classe `BestEffort` e é o primeiro
candidato a despejo quando o nó fica sob pressão.

Os valores de `requests` também são a base de cálculo do HPA
([nível 7](nivel-7-hpa.md)): sem eles, não há percentual de utilização a medir.

## Escala

A API roda com `replicas: 2`. Como não guarda estado entre requisições — tudo vive no
Postgres — qualquer réplica atende qualquer requisição, e o Service distribui a carga
automaticamente entre os endpoints.

Verificação: cada réplica mantém seu próprio pool de conexões, então o banco deve enxergar
conexões vindas de dois IPs distintos, iguais aos dois endpoints do Service.

```bash
kubectl get endpoints postgrest -n desafio-k8s
kubectl exec deployment/postgres -n desafio-k8s -- psql -U desafio_user -d desafio_db \
  -c "SELECT client_addr, count(*) FROM pg_stat_activity WHERE client_addr IS NOT NULL GROUP BY client_addr;"
```

![Réplicas, endpoints do Service e conexões de ambas no banco](evidencias/nivel-6-probes-escala.png)

## Por que o banco não escala do mesmo jeito

O Postgres permanece em `replicas: 1`, e isso não é omissão. O PVC é `ReadWriteOnce`: um
segundo Pod ficaria preso em `Pending`, esperando um volume que o primeiro não solta. E
mesmo que o volume fosse compartilhável, duas instâncias escrevendo no mesmo diretório de
dados sem coordenação corromperiam o banco — o Postgres não foi projetado para isso.

Escalar um banco relacional exige replicação em nível de aplicação: um primário para
escrita, réplicas de leitura com streaming replication, e roteamento consciente dessa
topologia. É mudança de arquitetura, não de um campo no manifest.
