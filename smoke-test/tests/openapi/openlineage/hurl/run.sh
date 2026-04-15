#!/usr/bin/env bash
# OpenLineage Hurl suite runner with bulletproof per-request GMS log attribution.
#
# Each hurl request is tagged with a unique `User-Agent: hurl/<run_id>/<file>-<req>`
# header. DataHub's RequestContext logs the UA, and this script post-processes
# `docker logs` to produce a per-request delta of exactly which MCPs were emitted.
#
# Usage:
#   ./run.sh                              # run full suite, print delta report
#   ./run.sh 02_event_types.hurl          # run one file
#   ./run.sh --reset                      # nuke DataHub state first (slow)
#   ./run.sh --container mygms -- *.hurl  # override container name
#
# Exit status: 0 if every request produced its expected HTTP status, non-zero otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONTAINER="${CONTAINER:-datahub-ingest-datahub-gms-1}"
RESET=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reset)       RESET=1; shift ;;
        --container)   CONTAINER="$2"; shift 2 ;;
        --)            shift; POS+=("$@"); break ;;
        -*)            echo "Unknown option: $1" >&2; exit 2 ;;
        *)             POS+=("$1"); shift ;;
    esac
done

if [[ ${#POS[@]} -eq 0 ]]; then
    while IFS= read -r f; do POS+=("$f"); done < <(ls -1 [0-9]*.hurl | grep -v workaround)
fi

if [[ $RESET -eq 1 ]]; then
    echo "[reset] nuking DataHub state via datahub-dev.sh..."
    ( cd "$(git rev-parse --show-toplevel)" && scripts/dev/datahub-dev.sh nuke --keep-data && scripts/dev/datahub-dev.sh start --wait )
fi

# Generate a fresh run_id: timestamp + short random tag.
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
MARK="$(date -u +%Y-%m-%dT%H:%M:%S)"

echo "[run] run_id=$RUN_ID"
echo "[run] log mark=$MARK"
echo "[run] files: ${POS[*]}"
echo "[run] container: $CONTAINER"
echo

HURL_REPORT="/tmp/hurl-report-$RUN_ID"
mkdir -p "$HURL_REPORT"

set +e
hurl --variables-file vars.env \
     --variable "run_id=$RUN_ID" \
     --test --continue-on-error \
     --report-json "$HURL_REPORT" \
     --connect-timeout 5 --max-time 30 \
     "${POS[@]}"
HURL_STATUS=$?
set -e

echo
echo "================================================================================"
echo " Per-request MCP delta (from docker logs --since $MARK, filtered by run_id=$RUN_ID)"
echo "================================================================================"

docker logs --since "$MARK" "$CONTAINER" 2>&1 \
  | grep -E "(LineageApiImpl:59 - Received lineage event|LineageApiImpl:93 - Ingesting MCP|ERROR i.d.o.o.controller|RequestContext.*userAgent='hurl/$RUN_ID)" \
  > "/tmp/gms-$RUN_ID.log" || true

python3 "$SCRIPT_DIR/parse_gms.py" "/tmp/gms-$RUN_ID.log" "$RUN_ID" "$MARK" "${POS[@]}"

exit $HURL_STATUS
