# Segurança e reprodutibilidade

Decisões que valem para todos os manifests, verificadas pelo Checkov no
[pipeline de CI](ci-cd.md).

## Imagens fixadas por digest

`postgres` e `postgrest` são referenciados por `sha256`, não por tag:

```yaml
image: postgres@sha256:f1c3376c26f2609ab9f29f71f824103fe2fcd8ee0346485cb6122a4f93df6f94
```

Uma tag é um ponteiro móvel: `:latest` — e mesmo `:16` — pode apontar para outra imagem
amanhã sem que nenhum arquivo mude, e o mesmo `kubectl apply` produz resultados diferentes
em momentos diferentes. Um digest identifica o conteúdo, não o rótulo: a imagem é
byte-a-byte a mesma em qualquer ambiente e em qualquer data. Atualização passa a ser um
commit explícito e revisável.

## Contexto de segurança dos containers

Ambos os Deployments aplicam:

```yaml
securityContext:          # Pod
  runAsNonRoot: true
  runAsUser: <uid>
  fsGroup: <gid>
securityContext:          # container
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

- **Não-root**: o Postgres roda como uid 999 (o usuário `postgres` da imagem), o PostgREST
  como uid 1000 (o padrão da imagem). Um processo comprometido não começa com privilégio
  administrativo dentro do container.
- **Filesystem raiz somente leitura**: os caminhos que precisam de escrita são declarados
  explicitamente — `PGDATA` no PVC, e `emptyDir` em `/tmp` e `/var/run/postgresql`.
  Qualquer escrita fora desses pontos falha.
- **Todas as capabilities removidas**: nenhum dos dois processos precisa de capability
  Linux — as portas usadas estão acima de 1024 e não há manipulação de rede ou de
  usuários em runtime. Rodar como uid fixo desde o início também elimina a necessidade de
  `SETUID`/`SETGID` que o entrypoint da imagem usaria para trocar de usuário.
- **`automountServiceAccountToken: false`**: nenhuma das aplicações fala com a API do
  Kubernetes, então o token não é montado.

## Credenciais como arquivo

Nenhuma credencial chega aos containers por variável de ambiente. O Postgres lê a senha
via `POSTGRES_PASSWORD_FILE`, e o PostgREST recebe a configuração inteira em
`/etc/postgrest/postgrest.conf`, ambos montados a partir do Secret com modo `0440`.
Detalhes em [configuração e credenciais](nivel-3-secret-configmap.md).

## Privilégio mínimo no banco

A API não se conecta como dono do banco. Existe um papel de conexão sem privilégios
(`authenticator`) e um papel de execução com exatamente as permissões que a API precisa
(`web_anon`: `SELECT` e `INSERT` em uma tabela). Detalhes e verificação automatizada em
[API conectada ao banco](nivel-4-postgrest-integracao.md).

## Estratégia de rollout do banco

O Deployment do Postgres usa `strategy: Recreate`. O padrão (`RollingUpdate`) cria o Pod
novo antes de remover o antigo, mas um PVC `ReadWriteOnce` só monta em um Pod por vez — o
Pod novo ficaria em `Pending` esperando um volume que não é liberado, e o rollout travaria.

`Recreate` troca disponibilidade contínua por consistência: há uma janela curta de
indisponibilidade a cada atualização, que é o comportamento correto para uma carga
stateful de instância única. Eliminar essa janela exige replicação de verdade, não outra
estratégia de rollout.

## Rótulos padrão

Todos os recursos carregam o conjunto recomendado pela documentação do Kubernetes
(`app.kubernetes.io/name`, `/instance`, `/part-of`, `/managed-by`), usado por ferramentas
de observabilidade e GitOps para agrupar recursos relacionados.

Os rótulos de `selector` (`app: postgres` / `app: postgrest`) foram mantidos inalterados:
`spec.selector` é imutável depois que o Deployment existe, e alterá-lo exigiria recriar o
recurso.
