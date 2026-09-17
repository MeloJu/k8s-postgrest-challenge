# Nível 3 — Configuração e segredos

## Objetivo

Mover as credenciais do PostgreSQL para um Secret e a configuração não sensível para um
ConfigMap, em vez de deixá-las escritas diretamente no Deployment.

## O que foi feito

### 1. Secret ([`k8s/01-postgres-secret.yaml`](../k8s/01-postgres-secret.yaml))

```yaml
stringData:
  POSTGRES_USER: <definido no arquivo aplicado>
  POSTGRES_PASSWORD: <definido no arquivo aplicado>
```

Os valores reais ficam só em [`k8s/01-postgres-secret.yaml`](../k8s/01-postgres-secret.yaml) —
não repetidos aqui, pra não duplicar a credencial em texto solto pela documentação.

Usei `stringData` (não `data`): o valor fica em texto plano no arquivo, e é o próprio
`kubectl apply` quem faz a codificação base64 ao enviar pro cluster. Se fosse `data`, cada
valor precisaria já vir base64-encodado à mão.

### 2. ConfigMap ([`k8s/02-postgres-configmap.yaml`](../k8s/02-postgres-configmap.yaml))

```yaml
data:
  POSTGRES_DB: desafio_db
  PGDATA: /var/lib/postgresql/data/pgdata
```

Nome do banco e caminho do `PGDATA` não são segredo — são só configuração, por isso vão
num ConfigMap em vez de Secret.

### 3. Deployment atualizado ([`k8s/04-postgres-deployment.yaml`](../k8s/04-postgres-deployment.yaml))

Cada variável de ambiente trocou de um `value:` literal para um `valueFrom`:

```yaml
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-secret
      key: POSTGRES_PASSWORD
```

O valor real nunca aparece neste arquivo — só a referência a onde buscá-lo. Reaplicar o
Deployment com esse env alterado disparou um rolling update automático (o Kubernetes
recriou o Pod sozinho com as novas variáveis).

```bash
kubectl apply -f k8s/01-postgres-secret.yaml
kubectl apply -f k8s/02-postgres-configmap.yaml
kubectl apply -f k8s/04-postgres-deployment.yaml
kubectl get pods -n desafio-k8s -w
kubectl exec -it deployment/postgres -n desafio-k8s -- psql -U desafio_user -d desafio_db -c "SELECT current_database();"
```

## ⚠️ Nota de segurança: por que o Secret está commitado no repositório

O arquivo `k8s/01-postgres-secret.yaml` está versionado neste repositório com uma senha
em texto plano (`stringData`). **Isso não é prática de produção** — é uma decisão
consciente para este desafio, pelos seguintes motivos:

- A credencial é descartável: protege apenas um PostgreSQL local, dentro de um cluster
  `kind` que é destruído ao final do exercício. Não há nenhum dado ou sistema real exposto.
- O próprio critério de aceitação do desafio exige que o avaliador consiga **ver** o
  Secret no repositório para confirmar que as credenciais saíram do Deployment.

Em um ambiente real, nenhuma dessas duas justificativas se sustentaria, e o valor jamais
deveria ir para o Git — nem em repositório privado. As alternativas usadas na indústria:

- **Não versionar o valor**: o pipeline de CI/CD injeta a credencial em tempo de deploy
  (a partir de um segredo do próprio GitHub Actions, por exemplo), e só a existência do
  Secret — não seu conteúdo — fica no manifest.
- **Sealed Secrets** (Bitnami): o valor é criptografado com uma chave pública antes do
  commit; só o controller rodando dentro do cluster (dono da chave privada) consegue
  decifrar. O que entra no Git é cifra de verdade, não base64.
- **External Secrets Operator / Vault**: o cluster busca a credencial de um cofre externo
  (AWS Secrets Manager, HashiCorp Vault) em tempo de execução — o Git nunca guarda o valor,
  só uma referência a onde buscá-lo.

Essa mesma tensão vai aparecer de novo quando o `ci.yml` (com Checkov) for montado: a
ferramenta provavelmente vai sinalizar este arquivo como um finding de "Secret em texto
plano". O tratamento correto não é silenciar o alerta, e sim documentá-lo como um risco
aceito e justificado — que é exatamente o que esta seção está fazendo.

## Evidências

Estado do cluster após a migração para Secret/ConfigMap, e conexão confirmada com as
credenciais vindas do Secret:

![Pods, Secret, ConfigMap e conferência via psql](evidencias/nivel-3-secret-configmap.png)

O Secret "cru" (`-o yaml`) e a prova de que o base64 é trivialmente reversível:

![Secret decodificado com base64 -d](evidencias/nivel-3-secret-base64-reveal.png)

## Reflexão

**Ao inspecionar o Secret com `-o yaml`, o valor aparece "embaralhado". Isso é
criptografia de verdade ou apenas codificação? O que isso significa para a segurança
real?**

É apenas codificação — base64, não criptografia. A diferença é fundamental: criptografia
exige uma chave para reverter o processo; codificação é só uma troca de representação,
reversível por qualquer um, sem chave nenhuma.

A prova está na própria evidência acima: o valor codificado do Secret volta a ser a senha
original com um único comando, `base64 -d`, sem nenhuma chave adicional (os valores em si
não são repetidos aqui em texto — só na imagem, que já é a evidência do comando real).
Qualquer pessoa com permissão de leitura sobre o objeto Secret (ou acesso direto ao etcd,
onde o cluster armazena esses dados) recupera a credencial original instantaneamente.

O que isso significa na prática: o Secret do Kubernetes **não protege o valor em si** —
ele só evita que a credencial apareça *acidentalmente* em `kubectl get -o yaml` de outros
recursos, ou hardcoded dentro de um Deployment. A segurança real de um Secret vem de
controles em volta dele, não do formato do dado:

- **RBAC** restringindo quem pode fazer `get`/`list` em Secrets no namespace.
- **Encryption at rest** no etcd (não habilitado por padrão em clusters locais como o `kind`).
- **Ferramentas externas** (Sealed Secrets, Vault, External Secrets Operator) para nunca
  deixar o valor em texto plano acessível via `kubectl` nem versionado em Git.

Sem esses controles, um Secret do Kubernetes é, na prática, equivalente a um ConfigMap
com uma etiqueta "sensível" — a codificação sozinha não impede ninguém com acesso de
recuperar o dado original.
