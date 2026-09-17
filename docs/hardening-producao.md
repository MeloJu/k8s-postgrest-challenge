# Decisões de hardening além do desafio

Este documento registra melhorias aplicadas a todos os manifests depois que os 7 níveis
do desafio já estavam funcionando, pensando no repositório como um projeto real, não só
como entrega de exercício. Nenhuma delas era exigida pelos critérios de aceitação — são
práticas de produção que valem a pena independente disso.

## 1. Imagens fixadas por versão/digest

**Antes**: `postgres:16` e `postgrest/postgrest:latest`.

**Depois**: `postgres:16.15` (versão exata) e
`postgrest/postgrest@sha256:ec0e25a4e24b0a3bc5e4f011369bfc736bd1b19f513bd01079b86329a7636962`
(digest exato, resolvido a partir da tag `:latest` em 2026-09-17 — na época,
correspondia à versão PostgREST 16.3).

Uma tag flutuante como `:latest` ou `:16` pode apontar para uma imagem diferente amanhã,
sem que nenhum YAML mude — o mesmo `kubectl apply` pode se comportar diferente em
momentos diferentes. Fixar por digest é a forma mais rigorosa de garantir que o que roda
em qualquer ambiente é **exatamente** a mesma imagem, byte a byte.

## 2. Labels padrão do Kubernetes

Todos os recursos (antes só o Namespace tinha) ganharam o conjunto recomendado pela
[documentação oficial](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/):
`app.kubernetes.io/name`, `/instance`, `/part-of`, `/managed-by`. Isso não muda
comportamento nenhum — é metadado — mas é o que ferramentas de terceiros (Lens, ArgoCD,
dashboards) usam pra agrupar e exibir recursos relacionados de forma legível.

Importante: o label usado nos `selector.matchLabels` (`app: postgres` / `app: postgrest`)
**não foi alterado** — esse campo é imutável depois que o Deployment existe, e trocá-lo
exigiria recriar o recurso do zero. Os labels novos foram só **adicionados** ao lado dele.

## 3. `strategy.type: Recreate` no Deployment do Postgres

Esta é a correção mais importante desta rodada, não só estética.

A estratégia padrão de rollout de um Deployment é `RollingUpdate`, que tenta subir o Pod
novo **antes** de derrubar o antigo (pra não ter downtime). Isso funciona bem para
aplicações sem estado como o PostgREST — mas o Postgres está com `replicas: 1` montando
um PVC `ReadWriteOnce`, que só pode ser montado por um Pod por vez. Com `RollingUpdate`,
o Pod novo ficaria preso em `Pending` esperando um volume que o Pod antigo ainda não
liberou, e o rollout travaria.

Com `strategy.type: Recreate`, o Kubernetes garante que o Pod antigo é **totalmente
terminado** (e libera o PVC) antes de criar o substituto. Isso significa um pequeno
período de indisponibilidade a cada atualização do Postgres — um trade-off aceitável e
correto para uma carga stateful de réplica única, muito melhor do que um rollout que
trava silenciosamente.

## 4. `resources` e probes também no Postgres

O desafio pedia probes e limits explicitamente só "na API" (Nível 6). Estendi os dois
para o Postgres também:

- `resources.requests`/`limits`: mesma lógica do Nível 6 — sem isso, o Postgres concorre
  por CPU/memória sem nenhum teto, podendo afetar outros Pods do nó.
- `livenessProbe`/`readinessProbe` via `pg_isready` (a ferramenta oficial do Postgres
  pra checar se o servidor está aceitando conexões): mais preciso que só checar se o
  processo existe — confirma que o banco está de fato pronto para receber queries.

## 5. Achados reais do Checkov (rodado pelo `ci.yml`)

Assim que o `ci.yml` rodou pela primeira vez, o Checkov encontrou 26 findings reais nos
Deployments. Em vez de aplicar todos cegamente, tratei cada um pela relação
risco/benefício:

**Corrigidos** (baixo risco, sem impacto funcional):

- `CKV_K8S_43` (imagem deveria usar digest) — o Postgres ainda estava só com a tag
  `16.15`; fixei por digest também, como já tinha feito com o PostgREST.
- `CKV_K8S_15` (Image Pull Policy deveria ser `Always`) — adicionado nos dois.
- `CKV_K8S_38` (Service Account Token só deve ser montado onde necessário) —
  `automountServiceAccountToken: false` nos dois Pods (nenhum dos dois fala com a API do
  Kubernetes, então o token nunca é usado).
- `CKV_K8S_31` (seccomp profile) — `RuntimeDefault` nos dois containers.
- `CKV_K8S_20`, `CKV_K8S_28`, `CKV_K8S_37` (privilege escalation e capabilities Linux) —
  `allowPrivilegeEscalation: false` e `capabilities.drop: ["ALL"]` **só no PostgREST**.
  Testado ao vivo: rollout completou, e a API continuou respondendo normalmente.

**Conscientemente não aplicados** (risco de quebrar algo que já funciona, validado):

- `CKV_K8S_20`/`CKV_K8S_28`/`CKV_K8S_37` **no Postgres**: a imagem oficial do Postgres
  usa `gosu` no entrypoint pra trocar de root para o usuário `postgres` — isso exige as
  capabilities `SETUID`/`SETGID`. Remover todas as capabilities quebraria a
  inicialização do container. Não vale o risco pra um ganho que é só metadado de scanner.
- `CKV_K8S_23`/`CKV_K8S_29`/`CKV_K8S_30` (rodar como non-root / `securityContext`
  completo): pelo mesmo motivo — o entrypoint do Postgres precisa iniciar como root pra
  ajustar permissões do diretório de dados antes de fazer o drop de privilégio sozinho.
  Forçar `runAsNonRoot: true` de fora quebraria esse processo.
- `CKV_K8S_22` (filesystem somente leitura): tanto o Postgres (escreve WAL, dados, locks)
  quanto o PostgREST (pode precisar de arquivos temporários) dependem de escrita fora do
  volume montado explicitamente. Aplicar isso exigiria mapear `emptyDir`s adicionais para
  cada caminho de escrita conhecido — não testei essa superfície inteira, e prefiro não
  aplicar um controle de segurança sem validar que não quebra nada.
- `CKV_K8S_35` (preferir Secrets montados como arquivo a variáveis de ambiente): o
  Postgres oficial suporta isso nativamente via `POSTGRES_PASSWORD_FILE` — daria pra
  migrar com baixo risco. O PostgREST, porém, não tem um equivalente documentado pra
  `PGRST_DB_URI` vindo de arquivo; migrar exigiria um script de entrypoint customizado
  lendo o arquivo e exportando a variável, o que é escopo maior do que cabe nesta rodada
  de hardening. Registrado aqui como próximo passo possível, não como pendência ignorada.

Nenhum desses itens não corrigidos é uma "falha" no sentido de quebrar o funcionamento —
são trade-offs de segurança vs. estabilidade, e a decisão de não aplicá-los foi feita
conscientemente, não por desconhecimento. Um scanner de segurança aponta possibilidades;
cabe a quem mantém o sistema avaliar o custo real de cada uma.

## Validação

Todas as mudanças foram aplicadas e testadas no cluster já em funcionamento: o rollout
do Postgres com `Recreate` completou sem ficar preso, os dados da tabela `todos`
sobreviveram à recriação, e o PostgREST continuou respondendo normalmente após o
deployment ser atualizado com a imagem fixada.
