# Event-type dispatch: RunEvent / JobEvent / DatasetEvent.
# Spec: OpenLineage 2-0-2 root oneOf.
#   - RunEvent.required:     [run, job]
#   - JobEvent.required:     [job]       (must NOT carry `run`)
#   - DatasetEvent.required: [dataset]   (must NOT carry `job` or `run`)
# RFC appendix A.1. Currently failing rows: JobEvent (#15196), DatasetEvent (no path).

# --- RunEvent (baseline) ------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r01-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:00.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "11111111-1111-1111-1111-111111111111" },
  "job":  { "namespace": "ci", "name": "etl_pipeline.load_users" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs":  [ { "namespace": "postgres://db.example.com:5432", "name": "raw.users" } ],
  "outputs": [ { "namespace": "postgres://db.example.com:5432", "name": "warehouse.users" } ]
}
HTTP 200

# --- JobEvent: no `run` block; spec-valid; currently NPEs (#15196) ------------
# (No embedded SchemaDatasetFacet — keeps this request focused on dispatch.)
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r02-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:01.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/JobEvent",
  "job":     { "namespace": "Customer Relationship Management", "name": "load_dp_customer" },
  "inputs":  [ { "namespace": "customer_unload",   "name": "customer" } ],
  "outputs": [ { "namespace": "dataproducts",       "name": "dp_customer" } ]
}
HTTP 200

# --- DatasetEvent: no `job` and no `run`; spec-valid; currently no dispatch ---
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r03-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:02.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/DatasetEvent",
  "dataset": {
    "namespace": "s3://my-bucket",
    "name": "events/2026/04/14",
    "facets": {
      "schema": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-1-1/SchemaDatasetFacet.json",
        "fields": [
          { "name": "event_id",   "type": "string" },
          { "name": "event_time", "type": "timestamp" }
        ]
      },
      "dataSource": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-1/DatasourceDatasetFacet.json",
        "name": "s3://my-bucket",
        "uri":  "s3://my-bucket/events"
      }
    }
  }
}
HTTP 200

# --- JobEvent carrying a `run` block: spec violation -------------------------
# The JobEvent definition in OpenLineage.json excludes `run`; events with both
# `job` and `run` are RunEvents. A `JobEvent` schemaURL + `run` block is
# ambiguous and must be rejected rather than silently dispatched as a RunEvent.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r04-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:03.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/JobEvent",
  "job":  { "namespace": "ci", "name": "bad_job_event" },
  "run":  { "runId": "11111111-2222-3333-4444-555555555555" }
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- DatasetEvent carrying a `job` block: spec violation ---------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r05-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:04.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/DatasetEvent",
  "dataset": { "namespace": "s3://b", "name": "k" },
  "job":     { "namespace": "ci", "name": "bad_dataset_event" }
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- DatasetEvent carrying a `run` block: spec violation ---------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r06-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:05.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/DatasetEvent",
  "dataset": { "namespace": "s3://b", "name": "k" },
  "run":     { "runId": "22222222-3333-4444-5555-666666666666" }
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- DatasetEvent missing required `dataset` field ---------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r07-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:06.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/DatasetEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- DatasetEvent.dataset missing namespace (Dataset.required: [namespace, name])
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r08-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:07.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/DatasetEvent",
  "dataset": { "name": "k" }
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- DatasetEvent.dataset missing name (Dataset.required: [namespace, name]) -
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r09-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:08.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/DatasetEvent",
  "dataset": { "namespace": "s3://b" }
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- RunEvent with empty `inputs` and `outputs` arrays: spec-legal -----------
# Arrays are optional per spec; an empty array is semantically identical to
# absent. Exercised explicitly so a later "non-null required" regression is
# caught.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r10-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:09.000Z",
  "eventType": "START",
  "run":  { "runId": "11111111-2222-3333-4444-eeeeeeeeeeee" },
  "job":  { "namespace": "ci", "name": "no_datasets.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs":  [],
  "outputs": []
}
HTTP 200

# --- schemaURL pinned to 2-0-0 (not 2-0-2) with `definitions` path ----------
# OpenLineage's own Python client emits
# `https://openlineage.io/spec/2-0-0/OpenLineage.json#/$defs/RunEvent` in
# serde fixtures. Real producers emit arbitrary historical version strings
# including the pre-`$defs` `#/definitions/` path. The endpoint should accept
# any spec-shaped envelope regardless of the literal schemaURL value;
# dispatch discriminates on payload shape, not on string equality with a
# hardcoded schemaURL.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f02-r11-event_types
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T10:00:10.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "11111111-2222-3333-4444-ffffffffffff" },
  "job":  { "namespace": "ci", "name": "legacy_schema_url.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-0/OpenLineage.json#/definitions/RunEvent"
}
HTTP 200
