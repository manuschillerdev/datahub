#!/usr/bin/env python3
"""Attribute DataHub GMS log entries back to individual Hurl requests.

Reads a pre-filtered log file (produced by `run.sh` via `docker logs --since`),
walks each Jetty worker thread sequentially, splits each thread's activity at
every `Received lineage event:` marker, and labels the resulting request blocks
by the `User-Agent` header that DataHub's `RequestContext` logs.

Produces a compact per-request delta: (test tag) → (entities/aspects emitted),
or (test tag) → (error signature) for failed requests.

Usage:
    parse_gms.py <log_file> <run_id> <mark_ts> <hurl_file1> [<hurl_file2> ...]

The tag format is `f<NN>-r<MM>-<slug>`, matching the per-request User-Agent
injected by `inject_ua.py` into the `.hurl` source files.
"""
from __future__ import annotations

import os
import re
import sys
from collections import defaultdict
from typing import Optional


def parse_log(path: str) -> list[dict]:
    """Walk each worker thread and split it at every `Received lineage event:`.

    Returns a list of request dicts with: ts, thread, mcps, err, user_agent.
    """
    threads: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    line_re = re.compile(r"^(\S+ \S+) \[([^\]]+)\] (\w+)\s+\S+\s+-\s+(.*)$")
    for line in open(path, encoding="utf-8", errors="replace"):
        m = line_re.match(line.rstrip())
        if not m:
            continue
        ts, thread, level, message = m.groups()
        threads[thread].append((ts, level, message))

    mcp_re = re.compile(
        r"aspectName=(\w+), entityUrn=(\S+?), entityType=(\w+), changeType=(\w+)"
    )
    ua_re = re.compile(r"userAgent='([^']+)'")

    requests: list[dict] = []
    for thread, events in threads.items():
        current: Optional[dict] = None
        for ts, level, message in events:
            if message.startswith("Received lineage event:"):
                if current:
                    requests.append(current)
                current = {
                    "ts": ts,
                    "thread": thread,
                    "mcps": [],
                    "err": None,
                    "user_agent": None,
                }
            elif current is None:
                continue
            elif "RequestContext" in message and "userAgent=" in message:
                m2 = ua_re.search(message)
                if m2:
                    current["user_agent"] = m2.group(1)
            elif message.startswith("Ingesting MCP:"):
                m2 = mcp_re.search(message)
                if m2:
                    # (entity_type, aspect_name, urn, change_type)
                    current["mcps"].append(
                        (m2.group(3), m2.group(1), m2.group(2), m2.group(4))
                    )
            elif level == "ERROR":
                # Classify into a short signature so the report stays compact.
                if "EventType" in message:
                    current["err"] = "null eventType (NPE)"
                elif "Job.getName" in message:
                    current["err"] = "null job.name (NPE)"
                elif "Run.getFacets" in message or "getRun()" in message:
                    current["err"] = "null run (NPE on JobEvent)"
                elif "Unable to determine orchestrator" in message:
                    current["err"] = "orchestrator allow-list"
                elif "ZonedDateTime" in message or "DateTimeParse" in message:
                    current["err"] = "bad eventTime"
                elif "ValidationException" in message and "$UNKNOWN" in message:
                    current["err"] = "DPI run-event $UNKNOWN enum"
                elif "ValidationException" in message:
                    current["err"] = "aspect validation"
                else:
                    current["err"] = message[:100]
        if current:
            requests.append(current)
    return requests


def expected_hurl_requests(files: list[str]) -> list[tuple[str, int, str]]:
    """Enumerate the (file_tag, request_index, slug) tuples declared by the
    User-Agent headers inside each .hurl source file. The tag matches exactly
    what `run.sh` passes through as `hurl/<run_id>/<tag>`.
    """
    ua_re = re.compile(r"^User-Agent:\s*hurl/\{\{run_id\}\}/(\S+)$")
    out: list[tuple[str, int, str]] = []
    for f in files:
        if not os.path.exists(f):
            continue
        for ln in open(f, encoding="utf-8"):
            m = ua_re.match(ln.strip())
            if m:
                out.append((f, len(out) + 1, m.group(1)))
    return out


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    log_path, run_id, _mark, *hurl_files = sys.argv[1:]

    requests = parse_log(log_path)
    expected = expected_hurl_requests(hurl_files)

    # Index captured requests by User-Agent for precise attribution.
    by_ua: dict[str, dict] = {}
    orphans: list[dict] = []
    for request in requests:
        ua = request.get("user_agent")
        if ua and ua.startswith(f"hurl/{run_id}/"):
            tag = ua[len(f"hurl/{run_id}/"):]
            by_ua[tag] = request
        elif ua and ua.startswith("hurl/"):
            # Different run_id — stale log line leaking in from a prior invocation.
            continue
        else:
            orphans.append(request)

    # Baseline aspect set (RunEvent path without inputs/outputs).
    # Used to compute "extra" emissions when inputs/outputs or facet data should
    # have produced more.
    print(f"{'Test':48s} {'HTTP result':22s} {'Aspects emitted (deduped by entity:aspect)'}")
    print("-" * 160)
    total, ok, failed = 0, 0, 0
    missing_ua = 0

    for hurl_file, _idx, tag in expected:
        total += 1
        request = by_ua.get(tag)
        if request is None:
            print(f"{tag:48s} {'? (no log match)':22s} -")
            missing_ua += 1
            continue

        aspects_by_entity: dict[str, set[str]] = defaultdict(set)
        for entity_type, aspect_name, _urn, change_type in request["mcps"]:
            label = aspect_name if change_type == "UPSERT" else f"{aspect_name}*{change_type}"
            aspects_by_entity[entity_type].add(label)

        if request["err"]:
            status = f"✘ {request['err']}"
            failed += 1
        else:
            status = "✔ 200 OK"
            ok += 1

        summary = " | ".join(
            f"{entity}({','.join(sorted(aspects))})"
            for entity, aspects in sorted(aspects_by_entity.items())
        ) or "(none)"
        print(f"{tag:48s} {status:22s} {summary}")

    # Aggregate counts.
    all_mcps = sum(len(r["mcps"]) for r in by_ua.values())
    aspect_counter: dict[tuple[str, str, str], int] = defaultdict(int)
    for request in by_ua.values():
        for entity_type, aspect_name, _urn, change_type in request["mcps"]:
            aspect_counter[(entity_type, aspect_name, change_type)] += 1

    print()
    print(f"Correlation: {len(by_ua)}/{total} requests matched by User-Agent (run_id={run_id})")
    if missing_ua:
        print(f"  {missing_ua} requests had no matching log line — pre-dispatch rejection (Jackson, auth, etc.)")
    # Stale log blocks from prior runs sharing the container log ring buffer
    # are intentionally not reported here: they cannot collide with the current
    # run_id, and the log filter strips their RequestContext lines anyway.
    print(f"Results:     {ok} ok, {failed} failed, {all_mcps} MCPs total")
    print()
    print("Aspect totals (entity:aspect changeType → count):")
    for (entity, aspect, change), count in sorted(
        aspect_counter.items(), key=lambda x: (-x[1], x[0])
    ):
        print(f"  {count:4d}  {entity}:{aspect:32s} {change}")

    return 0 if failed == 0 and missing_ua == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
