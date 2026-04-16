#!/usr/bin/env bash
set -euo pipefail

VOLUME_NAME="${COLES_DATA_VOLUME:-coles-llm-shopper_coles_data}"
TOKEN_PATH="/app/data/state/keep_token.json"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but was not found on PATH." >&2
  exit 1
fi

cat >&2 <<'MSG'
Paste the full keep_token.json content, then press Ctrl+D.

The JSON must include:
  - email
  - master_token

MSG

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

cat > "$tmp_file"

python3 - "$tmp_file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"Invalid JSON: {exc}") from exc

missing = [key for key in ("email", "master_token") if not data.get(key)]
if missing:
    raise SystemExit(f"Missing required key(s): {', '.join(missing)}")

path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"Token JSON validated for {data['email']}", file=sys.stderr)
PY

docker run --rm -i \
  -v "${VOLUME_NAME}:/app/data" \
  alpine sh -c "mkdir -p /app/data/state && cat > '${TOKEN_PATH}' && chmod 600 '${TOKEN_PATH}'" \
  < "$tmp_file"

docker run --rm \
  -v "${VOLUME_NAME}:/app/data" \
  alpine sh -c "test -s '${TOKEN_PATH}' && ls -l '${TOKEN_PATH}'"

echo "Imported Keep token into Docker volume ${VOLUME_NAME}:${TOKEN_PATH}" >&2
