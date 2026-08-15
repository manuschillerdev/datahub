# Free-form `producer` URI per OpenLineage 2-0-2 §BaseEvent.producer. Every
# request is a positive: any URI a producer might plausibly emit must be
# accepted. `format: uri` negatives are deferred with JSON Schema validation
# (see RFC Future Work).
# RFC appendix A.1.
# Currently failing rows: custom (#16961), Trino built-in listener (#13011).

# --- Canonical OpenLineage URL ------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f04-r01-producer_uri
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T14:00:00.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "44444444-0000-0000-0000-000000000001" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Apache Airflow producer prefix -------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f04-r02-producer_uri
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T14:00:01.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "44444444-0000-0000-0000-000000000002" },
  "job":  { "namespace": "airflow", "name": "my_dag.my_task" },
  "producer":  "https://github.com/apache/airflow/providers/openlineage/2.0.0",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Trino built-in event listener URL (real-world; #13011) -------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f04-r03-producer_uri
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T14:00:02.000Z",
  "eventType": "START",
  "run":  { "runId": "44444444-0000-0000-0000-000000000003" },
  "job":  { "namespace": "trino://trino.example.com:8080", "name": "20260414_140002_00132_abcde" },
  "producer":  "https://github.com/trinodb/trino/plugin/trino-openlineage",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Custom in-house producer (#16961) ----------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f04-r04-producer_uri
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T14:00:03.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "44444444-0000-0000-0000-000000000004" },
  "job":  { "namespace": "my_namespace", "name": "my_job" },
  "producer":  "https://github.com/myorganization/myproducer/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Custom producer with a non-github URI ------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f04-r05-producer_uri
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T14:00:04.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "44444444-0000-0000-0000-000000000005" },
  "job":  { "namespace": "my_namespace", "name": "my_job" },
  "producer":  "https://example.com/data-platform/lineage-emitter/v3.2",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Producer with ProcessingEngineRunFacet — orchestrator should come from facet ---
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f04-r06-producer_uri
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T14:00:05.000Z",
  "eventType": "COMPLETE",
  "run":  {
    "runId": "44444444-0000-0000-0000-000000000006",
    "facets": {
      "processing_engine": {
        "_producer":  "https://example.com/data-platform/lineage-emitter/v3.2",
        "_schemaURL": "https://openlineage.io/spec/facets/1-1-1/ProcessingEngineRunFacet.json#/$defs/ProcessingEngineRunFacet",
        "name": "flink",
        "version": "1.18.1",
        "openlineageAdapterVersion": "1.45.0"
      }
    }
  },
  "job":  { "namespace": "streaming", "name": "session_aggregator" },
  "producer":  "https://example.com/data-platform/lineage-emitter/v3.2",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Non-http URI scheme: spec just requires a URI, not http(s) --------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f04-r07-producer_uri
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T14:00:06.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "44444444-0000-0000-0000-000000000007" },
  "job":  { "namespace": "lambda", "name": "event_processor.handler" },
  "producer":  "arn:aws:lambda:us-east-1:123456789012:function:event_processor",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# Note: negative tests for `producer` and `schemaURL` not being URIs are
# deferred. Java's `URI` parser is lenient enough to accept "my-tool" as a
# valid opaque URI, so enforcing `format: uri` strictness requires a JSON
# Schema validator. Tracked under the "JSON Schema validation for request
# payloads" entry in RFC Future Work.
