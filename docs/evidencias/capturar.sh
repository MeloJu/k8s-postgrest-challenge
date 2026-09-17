#!/usr/bin/env bash
# Uso: <comando> 2>&1 | docs/evidencias/capturar.sh <nome-do-arquivo>
# Gera docs/evidencias/<nome-do-arquivo>.png a partir do stdin.
set -euo pipefail

NOME="${1:?uso: comando | capturar.sh <nome-sem-extensao>}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

silicon \
  --language sh \
  --theme "Monokai Extended" \
  --background "#1e1e2e" \
  --pad-horiz 40 \
  --pad-vert 40 \
  --no-line-number \
  --shadow-blur-radius 0 \
  -o "${DIR}/${NOME}.png"

echo "Salvo em docs/evidencias/${NOME}.png"
