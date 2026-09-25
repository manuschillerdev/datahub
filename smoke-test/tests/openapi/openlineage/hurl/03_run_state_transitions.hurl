# RunEvent.eventType: full state machine.
# Spec: OpenLineage 2-0-2 §RunEvent.eventType (START, RUNNING, COMPLETE, ABORT, FAIL, OTHER).
# Marquez fixture parallel: api/src/test/resources/open_lineage/listener/.

# --- START → RUNNING → COMPLETE happy path ------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r01-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:00.000Z",
  "eventType": "START",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000001" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r02-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:01:00.000Z",
  "eventType": "RUNNING",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000001" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r03-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:05:00.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000001" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- START → FAIL with ErrorMessageRunFacet -----------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r04-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T11:00:00.000Z",
  "eventType": "START",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000002" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.broken" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r05-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T11:00:30.000Z",
  "eventType": "FAIL",
  "run": {
    "runId": "22222222-aaaa-0000-0000-000000000002",
    "facets": {
      "errorMessage": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/ErrorMessageRunFacet.json",
        "message": "Division by zero in transform step",
        "programmingLanguage": "PYTHON",
        "stackTrace": "Traceback (most recent call last):\n  File \"transform.py\", line 42\nZeroDivisionError"
      }
    }
  },
  "job":  { "namespace": "ci", "name": "etl_pipeline.broken" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- ABORT terminal state -----------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r06-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T12:00:00.000Z",
  "eventType": "ABORT",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000003" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.cancelled" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- OTHER (supplementary metadata, no state change) --------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r07-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T13:00:00.000Z",
  "eventType": "OTHER",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000004" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.metadata_only" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- eventType enum negatives -------------------------------------------------
# Spec: RunEvent.eventType is an enum of START/RUNNING/COMPLETE/ABORT/FAIL/OTHER.
# Values outside this set are spec violations.

# Unknown enum value.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r08-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T13:01:00.000Z",
  "eventType": "DONE",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000005" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.bad_enum" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# Case mismatch — enum values are UPPER-case per spec.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r09-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T13:02:00.000Z",
  "eventType": "complete",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000006" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.case_mismatch" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# Empty string — not in enum.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f03-r10-run_state_transitions
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T13:03:00.000Z",
  "eventType": "",
  "run":  { "runId": "22222222-aaaa-0000-0000-000000000007" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.empty_enum" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists
