"""
Teste automatizado de persistência (Nível 5 do desafio).

Pré-requisito: os manifests de k8s/ já devem estar aplicados num cluster acessível via
`kubectl` (o pipeline de CD faz isso antes de rodar pytest; localmente, rode
`kubectl apply -f k8s/` e espere os Pods ficarem Ready antes de rodar este arquivo).

O fixture `api_url` abre um `kubectl port-forward` para o Service da API e o encerra ao
final dos testes do módulo — o mesmo mecanismo usado manualmente durante o Nível 5.
"""

import subprocess
import time

import pytest
import requests

NAMESPACE = "desafio-k8s"
SERVICE = "postgrest"
LOCAL_PORT = 3000
REMOTE_PORT = 3000
POD_READY_TIMEOUT = "120s"


@pytest.fixture(scope="module")
def api_url():
    proc = subprocess.Popen(
        [
            "kubectl", "port-forward",
            "-n", NAMESPACE,
            f"svc/{SERVICE}",
            f"{LOCAL_PORT}:{REMOTE_PORT}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        _wait_for_port_forward(proc)
        yield f"http://localhost:{LOCAL_PORT}"
    finally:
        proc.terminate()
        proc.wait(timeout=10)


def _wait_for_port_forward(proc, timeout=15):
    """Espera a linha 'Forwarding from' aparecer no stdout do port-forward."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError("kubectl port-forward encerrou antes de conectar")
        line = proc.stdout.readline()
        if b"Forwarding from" in line:
            return
    raise TimeoutError("kubectl port-forward nao ficou pronto a tempo")


def test_api_is_reachable(api_url):
    resp = requests.get(f"{api_url}/todos", timeout=10)
    assert resp.status_code == 200


def test_data_survives_postgres_pod_deletion(api_url):
    # 1. Insere um dado via POST
    payload = {"title": "pytest-persistence-check"}
    resp = requests.post(
        f"{api_url}/todos",
        json=payload,
        headers={"Prefer": "return=representation"},
        timeout=10,
    )
    assert resp.status_code == 201
    inserted_id = resp.json()[0]["id"]

    # 2. Confirma que o dado é lido de volta
    resp = requests.get(f"{api_url}/todos", timeout=10)
    assert resp.status_code == 200
    ids_before = [row["id"] for row in resp.json()]
    assert inserted_id in ids_before

    # 3. Deleta o Pod do Postgres
    subprocess.run(
        ["kubectl", "delete", "pod", "-n", NAMESPACE, "-l", "app=postgres"],
        check=True,
        capture_output=True,
    )

    # 4. Espera o Pod novo ficar Ready
    subprocess.run(
        [
            "kubectl", "wait", "--for=condition=Ready", "pod",
            "-n", NAMESPACE, "-l", "app=postgres",
            f"--timeout={POD_READY_TIMEOUT}",
        ],
        check=True,
        capture_output=True,
    )

    # 5. Confirma que o dado sobreviveu. Retry porque o pool de conexoes do
    #    PostgREST pode precisar de uma tentativa falha pra descartar a conexao
    #    antiga (o mesmo 57P01 observado manualmente no Nivel 5).
    last_error = None
    for _ in range(6):
        try:
            resp = requests.get(f"{api_url}/todos", timeout=10)
            if resp.status_code == 200:
                ids_after = [row["id"] for row in resp.json()]
                if inserted_id in ids_after:
                    return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(2)

    pytest.fail(
        f"dado inserido (id={inserted_id}) nao sobreviveu a recriacao do Pod "
        f"do Postgres (ultimo erro: {last_error})"
    )
