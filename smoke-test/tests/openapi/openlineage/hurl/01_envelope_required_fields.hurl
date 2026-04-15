# Envelope: BaseEvent required fields (eventTime, producer, schemaURL) and
# RunEvent-specific required fields (run, job, run.runId, job.namespace,
# job.name). Also exercises non-JSON / wrong-media-type rejection.
# Spec: OpenLineage 2-0-2 §BaseEvent, §RunEvent.required, §Run.required,
# §Job.required.
# RFC appendix A.1.

# --- Minimum valid RunEvent (Marquez event_required_only.json) ----------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r01-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:01.641Z",
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36670" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Missing schemaURL: spec violation, must be rejected ----------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r02-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:01.641Z",
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36671" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer": "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Missing producer: spec violation, must be rejected -----------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r03-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:01.641Z",
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36672" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Missing eventTime: spec violation, must be rejected ----------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r04-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36673" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Empty body: must be rejected (not a 500) ---------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r05-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- RunEvent missing `run`: spec violation (RunEvent.required: [run, job]) ---
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r06-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:02.000Z",
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- RunEvent missing `job`: spec violation (RunEvent.required: [run, job]) ---
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r07-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:03.000Z",
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36674" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Run block present but missing runId: spec violation (Run.required) ------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r08-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:04.000Z",
  "run":  { },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Job block missing namespace: spec violation (Job.required) --------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r09-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:05.000Z",
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36675" },
  "job":  { "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Job block missing name: spec violation (Job.required) -------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r10-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:06.000Z",
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36676" },
  "job":  { "namespace": "my-namespace" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Unparseable JSON body: must be rejected as 400 (not 500) ----------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r11-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
```
{ this is : not json,,,
```
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Wrong Content-Type: Spring returns 415 (or 400) for text/plain ----------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r12-envelope_required_fields
Content-Type: text/plain
Authorization: Bearer {{token}}
```
eventTime=2026-04-14T19:51:07.000Z
```
HTTP 4xx

# --- Type-mismatch: `run` as a string instead of an object -------------------
# Jackson typed deserialization rejects this deterministically regardless of
# whether facet-level schema validation is wired in.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r13-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:08.000Z",
  "run":  "43d7db3b-8984-4cda-b237-8c6919b36677",
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Type-mismatch: `eventTime` as a number instead of a string --------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r14-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": 1776168000,
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36678" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists

# --- Type-mismatch: `inputs` as an object instead of an array ----------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f01-r15-envelope_required_fields
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:51:09.000Z",
  "run":  { "runId": "43d7db3b-8984-4cda-b237-8c6919b36679" },
  "job":  { "namespace": "my-namespace", "name": "myjob" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": { "namespace": "postgres://db", "name": "t" }
}
HTTP 400
[Asserts]
jsonpath "$.code"    exists
jsonpath "$.message" exists
