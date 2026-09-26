#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
exec mise exec -- uv run --no-project --python 3.11 scripts/dev/tls_lab.py "$@"
