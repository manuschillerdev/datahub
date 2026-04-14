# Workaround variant of 01_envelope_required_fields.hurl — adds an explicit
# `eventType: COMPLETE` to every request so we can observe what else the
# endpoint rejects after the missing-eventType NPE is hidden.

# --- Minimum valid RunEvent + eventType ---------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r01-envelope_required_fields_workaround
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventType": "COMPLETE",
  "eventTime": "2026-04-14T19:51:01.641Z",
  "run":  { "runId": "bbbbbbbb-0001-0000-0000-000000000001" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Missing schemaURL + eventType --------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r02-envelope_required_fields_workaround
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventType": "COMPLETE",
  "eventTime": "2026-04-14T19:51:01.641Z",
  "run":  { "runId": "bbbbbbbb-0001-0000-0000-000000000002" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer": "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client"
}
HTTP 400

# --- Missing producer + eventType ---------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r03-envelope_required_fields_workaround
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventType": "COMPLETE",
  "eventTime": "2026-04-14T19:51:01.641Z",
  "run":  { "runId": "bbbbbbbb-0001-0000-0000-000000000003" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400

# --- Missing eventTime + eventType --------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r04-envelope_required_fields_workaround
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventType": "COMPLETE",
  "run":  { "runId": "bbbbbbbb-0001-0000-0000-000000000004" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400

# --- eventType only (everything else missing) ---------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r05-envelope_required_fields_workaround
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventType": "COMPLETE"
}
HTTP 400
