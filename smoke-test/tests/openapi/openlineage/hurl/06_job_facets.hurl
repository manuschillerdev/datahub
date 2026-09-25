# Standard job facets — Documentation, SourceCodeLocation, SourceCode, SQL,
# Ownership, Tags, JobType.
# Spec: OpenLineage/spec/facets/*JobFacet.json.
# RFC appendix A.3.
# Currently failing: TagsJobFacet/OwnershipJobFacet (#14458), JobTypeJobFacet,
# SourceCodeLocationJobFacet, DocumentationJobFacet routed to wrong entity.

# --- DocumentationJobFacet ----------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r01-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:00.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "66666666-0000-0000-0000-000000000001" },
  "job": {
    "namespace": "ci",
    "name": "documented_pipeline.transform",
    "facets": {
      "documentation": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DocumentationJobFacet.json",
        "description": "Aggregates user activity into daily metrics. See https://wiki.example.com/etl/transform"
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- SourceCodeLocationJobFacet -----------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r02-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:01.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "66666666-0000-0000-0000-000000000002" },
  "job": {
    "namespace": "ci",
    "name": "git_tracked_pipeline.transform",
    "facets": {
      "sourceCodeLocation": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/SourceCodeLocationJobFacet.json",
        "type": "git",
        "url":  "https://github.com/example/etl-pipelines/blob/main/transform.py",
        "repoUrl": "https://github.com/example/etl-pipelines",
        "path": "transform.py",
        "version": "abc1234",
        "branch":  "main"
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- SQLJobFacet --------------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r03-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:02.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "66666666-0000-0000-0000-000000000003" },
  "job": {
    "namespace": "trino://trino.example.com:8080",
    "name": "sql_pipeline.create_table",
    "facets": {
      "sql": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-1/SQLJobFacet.json",
        "query": "CREATE TABLE warehouse.customer AS SELECT * FROM raw.customer WHERE active = true"
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- OwnershipJobFacet (#14458) -----------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r04-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:03.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "66666666-0000-0000-0000-000000000004" },
  "job": {
    "namespace": "ci",
    "name": "owned_pipeline.transform",
    "facets": {
      "ownership": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/OwnershipJobFacet.json",
        "owners": [
          { "name": "jdoe",  "type": "DEVELOPER" },
          { "name": "alice", "type": "STAKEHOLDER" }
        ]
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- TagsJobFacet (#14458) ----------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r05-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:04.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "66666666-0000-0000-0000-000000000005" },
  "job": {
    "namespace": "ci",
    "name": "tagged_pipeline.transform",
    "facets": {
      "tags": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/TagsJobFacet.json",
        "tags": [
          { "key": "environment", "value": "production",      "source": "CONFIG" },
          { "key": "team",        "value": "data-engineering", "source": "CONFIG" }
        ]
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- JobTypeJobFacet ----------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r06-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:05.000Z",
  "eventType": "START",
  "run":  { "runId": "66666666-0000-0000-0000-000000000006" },
  "job": {
    "namespace": "trino://trino.example.com:8080",
    "name": "20260414_160005_00132_abcde",
    "facets": {
      "jobType": {
        "_producer":  "https://github.com/trinodb/trino/plugin/trino-openlineage",
        "_schemaURL": "https://openlineage.io/spec/facets/2-0-3/JobTypeJobFacet.json#/$defs/JobTypeJobFacet",
        "processingType": "BATCH",
        "integration":    "TRINO",
        "jobType":        "QUERY"
      }
    }
  },
  "producer":  "https://github.com/trinodb/trino/plugin/trino-openlineage",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- SourceCodeJobFacet -------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r07-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:06.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "66666666-0000-0000-0000-000000000007" },
  "job": {
    "namespace": "ci",
    "name": "inline_code.transform",
    "facets": {
      "sourceCode": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/SourceCodeJobFacet.json",
        "language": "python",
        "sourceCode": "def transform(df):\n    return df.filter(df.active == True)"
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- JobTypeJobFacet with processingType=STREAMING ----------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r08-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:07.000Z",
  "eventType": "START",
  "run":  { "runId": "66666666-0000-0000-0000-000000000008" },
  "job": {
    "namespace": "flink://jobmanager.example.com:8081",
    "name": "session_aggregator",
    "facets": {
      "jobType": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/2-0-3/JobTypeJobFacet.json#/$defs/JobTypeJobFacet",
        "processingType": "STREAMING",
        "integration":    "FLINK",
        "jobType":        "STREAMING_JOB"
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- OwnershipJobFacet covering the spec-enumerated owner type values --------
# Spec: `type` is an open string per OwnershipJobFacet.json, but DataHub's
# documented mapping recognizes DEVELOPER / MAINTAINER / STAKEHOLDER /
# BUSINESS_OWNER / TECHNICAL_OWNER / DATA_STEWARD. Exercise the full set so
# any future enum tightening is caught.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f06-r09-job_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T16:00:08.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "66666666-0000-0000-0000-000000000009" },
  "job": {
    "namespace": "ci",
    "name": "fully_owned_pipeline.transform",
    "facets": {
      "ownership": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/OwnershipJobFacet.json",
        "owners": [
          { "name": "urn:li:corpuser:dev1",     "type": "DEVELOPER" },
          { "name": "urn:li:corpuser:main1",    "type": "MAINTAINER" },
          { "name": "urn:li:corpuser:stake1",   "type": "STAKEHOLDER" },
          { "name": "urn:li:corpGroup:owners",  "type": "BUSINESS_OWNER" },
          { "name": "urn:li:corpGroup:plat",    "type": "TECHNICAL_OWNER" },
          { "name": "urn:li:corpuser:steward1", "type": "DATA_STEWARD" }
        ]
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200
