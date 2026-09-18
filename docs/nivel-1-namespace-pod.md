# 1. Namespace e primeiro contato

## Namespace

Todos os recursos do projeto vivem em `desafio-k8s`, declarado em
[`k8s/00-namespace.yaml`](../k8s/00-namespace.yaml). Um Namespace dá escopo de nomes e
isolamento lógico: recursos homônimos podem coexistir em Namespaces diferentes, e a
maioria dos comandos `kubectl` só enxerga o Namespace corrente a menos que se passe `-n`.

## Pod avulso: por que não usamos

Antes de subir qualquer workload real, vale entender o comportamento de um Pod sem
controlador. Criado diretamente:

```bash
kubectl run test-pod --image=busybox:stable -n desafio-k8s \
  -- sh -c "while true; do echo hello from test-pod; sleep 5; done"
```

Inspecionado com `kubectl get`, `logs` e `describe`, três campos importam para o resto do
projeto:

- **IP do Pod** (`10.244.0.5` na execução): efêmero, muda a cada recriação. É por isso
  que a conexão da API com o banco usa o nome do Service, não IP ([nível 4](nivel-4-postgrest-integracao.md)).
- **QoS Class: BestEffort**, consequência de não declarar `requests`/`limits`. Corrigido
  no [nível 6](nivel-6-probes-escala.md).
- **Events** (`Scheduled → Pulling → Pulled → Created → Started`): o rastro que o
  control plane deixa. Primeiro lugar a olhar em `Pending` ou `CrashLoopBackOff`.

Ao deletar o Pod, ele **não volta**:

```bash
kubectl delete pod test-pod -n desafio-k8s
kubectl get pod -n desafio-k8s
# No resources found in desafio-k8s namespace.
```

## Evidências

![Namespace desafio-k8s](evidencias/nivel-1-namespace.png)

![Ciclo de vida do Pod avulso](evidencias/nivel-1-pod-lifecycle.png)

## Por que isso importa

Um Pod criado diretamente não tem controlador guardando um estado desejado; ele *é* o
estado. Quem recria Pods é um `ReplicaSet` (gerenciado por um `Deployment`), `StatefulSet`
ou `DaemonSet`, rodando um loop de reconciliação que compara réplicas desejadas com
réplicas existentes e repõe a diferença.

Sem esse loop, não há auto-recuperação de falha, sobrevivência a realocação de nó, rolling
update ou escala. Por isso PostgreSQL e PostgREST são `Deployment` desde o início.
