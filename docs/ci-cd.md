# CI/CD

## `ci.yml` — validação em Pull Requests

Roda em todo PR para `develop` ou `main`. Três jobs independentes, todos **soft-fail**
(reportam, não bloqueiam o merge — o objetivo aqui é visibilidade, não gate):

- **kubeconform**: valida a sintaxe e o schema de cada manifest em `k8s/` contra a versão
  do Kubernetes usada no projeto.
- **Checkov**: escaneia `k8s/` em busca de configurações de segurança arriscadas. Os
  achados reais dessa ferramenta guiaram boa parte de
  [`docs/hardening-producao.md`](hardening-producao.md).
- **Semgrep**: escaneia `tests/` (regras genéricas de qualidade/segurança em Python).

## `cd.yml` — deploy e teste em push para `main`

Roda em todo push pra `main` (ou seja, todo merge de PR, já que a branch é protegida).
**Hard-fail** — se falhar, o job falha de verdade:

1. Sobe um cluster `kind` efêmero (`helm/kind-action`) — do zero, sem nenhum estado
   anterior.
2. `kubectl apply -f k8s/`.
3. Espera todos os Pods do namespace ficarem `Ready`.
4. Roda `pytest tests/`, incluindo o teste automatizado de persistência.
5. Em caso de falha, despeja os logs do Postgres e do PostgREST pra facilitar o debug.

## Um bug real que o `cd.yml` encontrou na primeira execução

Na primeira vez que o pipeline rodou de ponta a ponta, o passo "esperar Pods ficarem
Ready" **falhou** — os dois Pods do PostgREST nunca saíam de `0/1`. O motivo, visível no
`kubectl describe pod` capturado pelo próprio job de debug:

```
Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 404
```

A causa: a tabela `todos` nunca foi criada por nenhum manifest. Durante o Nível 4, ela
foi criada manualmente com `kubectl exec ... psql -c "CREATE TABLE ..."` — um passo que
existia só na minha cabeça (e no terminal), nunca no repositório. O cluster de
desenvolvimento, rodando continuamente desde então, escondia esse problema: a tabela
sempre esteve lá porque nunca recriei o volume do zero. O cluster efêmero do `cd.yml`,
por definição, não tem esse histórico — e expôs exatamente a lacuna que testes manuais
não pegam: **o que só existe na minha máquina não é reproduzível**.

### Correção

Movida a criação da tabela pro mecanismo nativo da imagem oficial do Postgres —
qualquer script `.sql` colocado em `/docker-entrypoint-initdb.d/` roda automaticamente na
**primeira inicialização** de um volume vazio. Implementado em
[`k8s/02-postgres-configmap.yaml`](../k8s/02-postgres-configmap.yaml) (chave `init.sql`)
montado como arquivo em
[`k8s/04-postgres-deployment.yaml`](../k8s/04-postgres-deployment.yaml) via
`volumeMounts` + `subPath`.

Validado apagando o Namespace inteiro (forçando um volume genuinamente novo, replicando
o cenário do cluster efêmero) e reaplicando `kubectl apply -f k8s/` do zero: todos os
Pods ficaram `Ready` sozinhos, sem nenhum passo manual.

Essa é exatamente a razão de ter um `cd.yml` com cluster efêmero em vez de só testar
manualmente num cluster que já existe há dias — o ambiente de longa duração acumula
estado que mascara passos esquecidos na automação.
