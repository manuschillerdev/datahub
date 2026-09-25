# Strict-spec alternative to the Marquez-parity naive-tz positives in
# 10_unicode_and_edge_cases.hurl.
#
# The OpenLineage spec's `BaseEvent.eventTime` has `format: date-time`, which
# per RFC 3339 requires an offset. This file encodes the strict
# interpretation: naive timestamps (no `Z`, no offset) are spec violations
# and must be rejected with HTTP 400.
#
# The live suite ships the opposite contract — HTTP 200 with UTC coercion —
# because the OpenLineage reference Python client emits naive timestamps in
# its own serde fixtures
# (`client/python/tests/serde_example_run_event.json`:
# `"eventTime": "2021-11-03T10:53:52.427343"`), Marquez accepts them, and
# rejecting real ecosystem payloads would be hostile. See the companion
# positives at `10_unicode_and_edge_cases.hurl` r04 / r06 / r07.
#
# This file is excluded from the pytest runner
# (`test_openlineage_spec.py` filters `*_strict.hurl`). Run manually with
# `hurl 10_unicode_and_edge_cases_strict.hurl` if you want to test a
# configuration that has disabled the permissive `ZonedDateTime`
# deserializer (e.g. a future RFC that adds a `strictEventTime` knob).

# --- naive eventTime at millisecond precision — strict reject --------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10s-r01-unicode_and_edge_cases_strict
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T20:00:00.000",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-00000000000a" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- naive eventTime at second precision — strict reject ------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10s-r02-unicode_and_edge_cases_strict
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T20:00:00",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-00000000000b" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- OL Python client shape (microsecond naive) — strict reject -----------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10s-r03-unicode_and_edge_cases_strict
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2021-11-03T10:53:52.427343",
  "eventType": "START",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-00000000000c" },
  "job":  { "namespace": "workshop", "name": "process_taxes" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-0/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists
