# Scripts

Esta pasta existe para separar **a camada de plataforma da camada de aplicação**.

Os manifests em [`k8s/`](../k8s/) descrevem apenas a aplicação, e sobem com um comando:

```bash
kubectl apply -f k8s/
```

Mas a aplicação assume um cluster que já existe e que já tem o `metrics-server` rodando
(dependência do HPA). Esses pré-requisitos são responsabilidade de quem provisiona o
cluster, não da aplicação: em ambientes gerenciados como EKS, GKE e AKS o `metrics-server`
normalmente já vem instalado, e um manifest da aplicação tentando instalá-lo entraria em
conflito. Além disso, o patch de TLS necessário no `kind` é uma particularidade local que
não deve viajar junto com a aplicação.

Os scripts ocupam exatamente esse espaço: automatizam os passos de plataforma e a sequência
de comandos já documentada, sem misturá-los aos manifests.

## `setup.sh`

Sobe o ambiente inteiro do zero:

```bash
./scripts/setup.sh
```

Cria o cluster `kind` (se ainda não existir), instala o `metrics-server`, aplica os
manifests e aguarda os Pods ficarem prontos. É idempotente: rodar de novo em um ambiente
já montado não quebra nada.

O nome do cluster pode ser trocado com `CLUSTER_NAME=meu-cluster ./scripts/setup.sh`.

## `install-metrics-server.sh`

Instala e configura o `metrics-server` numa versão fixa (`v0.9.0`), incluindo o patch
`--kubelet-insecure-tls`, necessário porque o `kind` usa certificados autoassinados nos
kubelets. Sem esse ajuste o componente sobe mas nunca reporta métricas, e o HPA fica
inerte mostrando `<unknown>`.

Não é chamado diretamente no uso normal: o `setup.sh` e o workflow de
[CD](../.github/workflows/cd.yml) usam este mesmo arquivo. Manter o procedimento em um
lugar só evita que a documentação e o pipeline divirjam com o tempo.

## `load-test.sh`

Demonstra o autoscaling:

```bash
./scripts/load-test.sh [duracao_em_segundos]
```

Sobe um Pod gerador de carga dentro do cluster, acompanha o HPA aumentando as réplicas e,
ao final, remove a carga e mostra a redução de volta ao mínimo. A carga roda dentro do
cluster e acessa o Service pelo nome, sem depender de `port-forward`, que roda na máquina
host e não sustenta carga contínua de forma confiável.

O gerador é removido automaticamente ao final, inclusive se você interromper com `Ctrl+C`.
