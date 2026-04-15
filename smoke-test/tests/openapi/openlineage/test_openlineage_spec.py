"""
OpenLineage spec-compliance test suite.

Runs the Hurl fixtures in ``hurl/`` against the live GMS openlineage endpoint
and asserts the expected HTTP responses. This layer only validates request /
response shape — the post-RFC contract for
``POST /openapi/openlineage/api/v1/lineage``. Verification of the emitted
DataHub MCPs / aspects is intentionally out of scope for this suite and is
handled separately by the log-correlating ``hurl/run.sh`` wrapper.

The fixtures are the source of truth; see
``docs/rfcs/active/000-openlineage-spec-compliance.md`` for the contract they
encode. This test file is a thin adapter: each ``*.hurl`` file becomes one
parametrized test case so failures point at a specific spec area.

Requires the ``hurl`` binary (https://hurl.dev). If it is not installed the
whole module is skipped with an instructive message rather than silently
passing.
"""

import json
import logging
import os
import shutil
import subprocess
from pathlib import Path
from typing import List

import pytest

logger = logging.getLogger(__name__)

HURL_DIR = Path(__file__).parent / "hurl"
HURL_BIN = shutil.which("hurl")

pytestmark = pytest.mark.skipif(
    HURL_BIN is None,
    reason="hurl binary not found on PATH; install from https://hurl.dev",
)


def _discover_hurl_files() -> List[Path]:
    """Return the spec-compliance hurl files in deterministic order.

    Excludes:
    - ``*workaround*`` files — pre-RFC behavior that documents current bugs.
    - ``*_strict.hurl`` files — spec-strict sibling fixtures for contracts
      that ship relaxed by default (e.g. naive-timezone eventTime handling,
      which the live suite treats as Marquez-parity positives while the
      strict sibling encodes the RFC-3339 rejection path). Run manually
      via ``hurl *_strict.hurl`` when you want to test a spec-strict
      configuration.
    - ``legacy/`` — real-world producer payloads, tracked separately as a
      regression corpus.
    """
    files = sorted(
        p
        for p in HURL_DIR.glob("[0-9]*.hurl")
        if "workaround" not in p.name and not p.name.endswith("_strict.hurl")
    )
    return files


_HURL_FILES = _discover_hurl_files()


@pytest.mark.parametrize(
    "hurl_file",
    _HURL_FILES,
    ids=[p.name for p in _HURL_FILES],
)
def test_openlineage_spec_compliance(auth_session, hurl_file: Path, tmp_path: Path):
    """Exercise one hurl file against the live openlineage endpoint.

    A hurl file fails this test if any of its requests returns an HTTP status
    that doesn't match the spec-compliant contract the file encodes.
    """
    assert HURL_BIN is not None  # for type-checkers; guarded by pytestmark

    run_id = f"pytest-{os.getpid()}-{hurl_file.stem}"
    report_dir = tmp_path / "hurl-report"
    report_dir.mkdir()

    cmd = [
        HURL_BIN,
        "--test",
        "--continue-on-error",
        "--connect-timeout",
        "5",
        "--max-time",
        "30",
        "--variable",
        f"host={auth_session.gms_url()}",
        "--variable",
        f"token={auth_session.gms_token()}",
        "--variable",
        f"run_id={run_id}",
        "--report-json",
        str(report_dir),
        str(hurl_file),
    ]

    logger.info("running hurl: %s", " ".join(cmd))
    proc = subprocess.run(
        cmd,
        cwd=str(HURL_DIR),
        capture_output=True,
        text=True,
    )

    if proc.returncode == 0:
        return

    # On failure, surface the per-request breakdown from hurl's JSON report
    # so the pytest log points at the exact request index that broke.
    report_path = report_dir / "report.json"
    failures: List[str] = []
    if report_path.exists():
        try:
            report = json.loads(report_path.read_text())
            for entry in report:
                for idx, call in enumerate(entry.get("entries", [])):
                    calls = call.get("calls") or []
                    for c in calls:
                        resp = c.get("response", {})
                        status = resp.get("status")
                        asserts = call.get("asserts") or []
                        failed = [a for a in asserts if not a.get("success", True)]
                        if failed:
                            failures.append(
                                f"  [#{idx + 1}] http {status} — "
                                + "; ".join(
                                    a.get("message", "assert failed") for a in failed
                                )
                            )
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("could not parse hurl report %s: %s", report_path, e)

    message_lines = [
        f"hurl suite failed for {hurl_file.name} (exit={proc.returncode})",
    ]
    if failures:
        message_lines.append("failing requests:")
        message_lines.extend(failures)
    if proc.stdout.strip():
        message_lines.append("--- hurl stdout ---")
        message_lines.append(proc.stdout.strip())
    if proc.stderr.strip():
        message_lines.append("--- hurl stderr ---")
        message_lines.append(proc.stderr.strip())

    pytest.fail("\n".join(message_lines))
