# Edge cases — Unicode in names, nanosecond timestamps, no-timezone timestamps,
# event without schemaURL.
# Marquez fixtures: event_unicode.json, event_required_nanoseconds.json,
# event_required_no_timezone.json, event_without_schema_url.json.

# --- Unicode in job and dataset names -----------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10-r01-unicode_and_edge_cases
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T20:00:00.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-000000000001" },
  "job":  { "namespace": "münchen", "name": "tägliche_aggregation.lädt_kunden" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/lager",
      "name": "kundendaten_täglich"
    }
  ]
}
HTTP 200

# --- Nanosecond-precision eventTime -------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10-r02-unicode_and_edge_cases
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T20:00:00.123456789Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-000000000002" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- eventTime with explicit non-UTC offset -----------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10-r03-unicode_and_edge_cases
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T20:00:00.001+10:00",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-000000000003" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- eventTime without any timezone (ms precision): Marquez-parity positive --
# Spec-letter: `format: date-time` requires an offset. Spec-practice: the
# OpenLineage reference Python client serializes timestamps without a
# timezone suffix (`client/python/tests/serde_example_run_event.json`),
# Marquez accepts them, and real producers in the wild emit them. The
# openapi-servlet's ObjectMapper installs a permissive `ZonedDateTime`
# deserializer that falls back to `LocalDateTime.parse(s).atZone(UTC)` on
# `DateTimeParseException`, so naive timestamps are treated as UTC rather
# than rejected. RFC §"Endpoint dispatch" names the configuration;
# Unresolved Questions §6 records the decision. The strict-spec
# alternative — reject with HTTP 400 — is encoded as a parallel fixture
# set in `10_unicode_and_edge_cases_strict.hurl`, excluded from the
# pytest runner by the `*_strict.hurl` filename convention.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10-r04-unicode_and_edge_cases
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T20:00:00.000",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-000000000004" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- eventTime as epoch milliseconds: not an ISO-8601 date-time --------------
# Distinguished from the naive-tz positives: epoch-ms is not a date-time
# string at all, just a numeric string. Cannot be coerced to UTC because
# there's no datetime structure to coerce. Rejected.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10-r05-unicode_and_edge_cases
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "1776168000000",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-000000000005" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- eventTime second-only precision with no Z/offset: naive-tz positive -----
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10-r06-unicode_and_edge_cases
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T20:00:00",
  "eventType": "COMPLETE",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-000000000006" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- OpenLineage Python client default shape: microsecond precision, no tz ---
# Exact shape emitted by the `openlineage-python` SDK's serde fixtures at
# `client/python/tests/serde_example_run_event.json`. Pinning this as a
# positive is the contract: whatever the reference producer emits, we ingest.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f10-r07-unicode_and_edge_cases
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2021-11-03T10:53:52.427343",
  "eventType": "START",
  "run":  { "runId": "aaaaaaaa-0000-0000-0000-000000000007" },
  "job":  { "namespace": "workshop", "name": "process_taxes" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-0/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200
