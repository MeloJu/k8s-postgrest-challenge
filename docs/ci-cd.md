# CI/CD

## `ci.yml`: validação em Pull Requests

Roda em PRs para `develop` e `main`. Três jobs independentes:

- **kubeconform**: valida sintaxe e schema de cada manifest contra a versão do Kubernetes
  usada no projeto.
- **Checkov**: análise estática de segurança sobre `k8s/`. Os achados dessa ferramenta
  guiaram as decisões em [segurança e reprodutibilidade](hardening-producao.md).
- **Semgrep**: análise estática sobre `tests/`.

Os três são soft-fail: reportam sem bloquear o merge. A função aqui é visibilidade
contínua; o gate real de correção é o `cd.yml`.

## `cd.yml`: deploy e teste em push para `main`

Hard-fail, em cluster efêmero criado do zero a cada execução:

1. Cria um cluster `kind` (`helm/kind-action`).
2. `kubectl apply -f k8s/`.
3. Aguarda todos os Pods ficarem `Ready`.
4. Roda `pytest tests/`: alcance da API, restrição de privilégio do papel anônimo e
   persistência do dado após destruição do Pod do banco.
5. Em caso de falha, despeja estado do cluster e logs dos dois componentes.

Cluster novo a cada execução é proposital: um ambiente de longa duração acumula estado
aplicado manualmente e mascara passos que faltam na automação.

## Caso real: o passo que só existia no meu terminal

Na primeira execução completa, o `cd.yml` falhou ao aguardar os Pods:

```
Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 404
```

A tabela `todos` não existia. Ela tinha sido criada manualmente com
`kubectl exec ... psql -c "CREATE TABLE ..."` durante o desenvolvimento e nunca virou
manifest. O cluster local, rodando há dias sem recriar o volume, sempre a teve, e por
isso o problema era invisível localmente.

A correção foi mover a criação do schema para `/docker-entrypoint-initdb.d/`, mecanismo
nativo da imagem do Postgres que executa scripts na primeira inicialização de um volume
vazio. Hoje o mesmo script também cria os papéis de acesso e alguns registros de exemplo,
em [`k8s/02-postgres-configmap.yaml`](../k8s/02-postgres-configmap.yaml), montado pelo
[Deployment do banco](../k8s/04-postgres-deployment.yaml).

Validação: `kubectl delete namespace` seguido de `kubectl apply -f k8s/` deixa o ambiente
inteiro funcional, sem intervenção manual.

Os registros de exemplo existem por usabilidade: quem instala vê a API respondendo com
dados reais no primeiro `GET`, sem precisar montar um `POST` antes. Eles não interferem no
teste de persistência, que insere e rastreia um registro próprio.
