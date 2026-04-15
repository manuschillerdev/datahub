# Standard run facets — NominalTime, Parent, ProcessingEngine, ExternalQuery,
# EnvironmentVariables, TagsRun, JobDependencies, ExtractionError,
# ExecutionParameters. ErrorMessage is covered in 03_run_state_transitions.hurl.
# Spec: OpenLineage/spec/facets/*RunFacet.json.
# RFC appendix A.2.

# --- NominalTimeRunFacet ------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r01-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:00:00.000Z",
  "eventType": "COMPLETE",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000001",
    "facets": {
      "nominalTime": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/NominalTimeRunFacet.json",
        "nominalStartTime": "2026-04-14T00:00:00Z",
        "nominalEndTime":   "2026-04-15T00:00:00Z"
      }
    }
  },
  "job":  { "namespace": "scheduled", "name": "daily_rollup.aggregate" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- ParentRunFacet -----------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r02-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:01:00.000Z",
  "eventType": "START",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000002",
    "facets": {
      "parent": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/ParentRunFacet.json",
        "run": { "runId": "11111111-2222-3333-4444-555555555555" },
        "job": { "namespace": "ci", "name": "parent_pipeline.orchestrator" }
      }
    }
  },
  "job":  { "namespace": "ci", "name": "parent_pipeline.child_task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- ProcessingEngineRunFacet -------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r03-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:02:00.000Z",
  "eventType": "COMPLETE",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000003",
    "facets": {
      "processing_engine": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-1-1/ProcessingEngineRunFacet.json#/$defs/ProcessingEngineRunFacet",
        "name": "spark",
        "version": "3.5.1",
        "openlineageAdapterVersion": "1.45.0"
      }
    }
  },
  "job":  { "namespace": "spark://cluster.example.com:7077", "name": "etl.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- ExternalQueryRunFacet ----------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r04-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:03:00.000Z",
  "eventType": "COMPLETE",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000004",
    "facets": {
      "externalQuery": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/ExternalQueryRunFacet.json",
        "externalQueryId": "bigquery-job-2026041500001",
        "source": "bigquery"
      }
    }
  },
  "job":  { "namespace": "bigquery", "name": "warehouse.daily_metrics" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- EnvironmentVariablesRunFacet ---------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r05-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:04:00.000Z",
  "eventType": "COMPLETE",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000005",
    "facets": {
      "environment-properties": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/EnvironmentVariablesRunFacet.json",
        "environmentVariables": [
          { "name": "AIRFLOW_CTX_DAG_ID",      "value": "daily_rollup" },
          { "name": "AIRFLOW_CTX_TASK_ID",     "value": "aggregate" },
          { "name": "AIRFLOW_CTX_EXECUTION_DATE", "value": "2026-04-14T00:00:00+00:00" }
        ]
      }
    }
  },
  "job":  { "namespace": "airflow", "name": "daily_rollup.aggregate" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- TagsRunFacet -------------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r06-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:05:00.000Z",
  "eventType": "COMPLETE",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000006",
    "facets": {
      "tags": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/TagsRunFacet.json",
        "tags": [
          { "key": "run.trigger", "value": "manual",     "source": "USER" },
          { "key": "priority",    "value": "high",       "source": "CONFIG" }
        ]
      }
    }
  },
  "job":  { "namespace": "ci", "name": "tagged_run.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- JobDependenciesRunFacet --------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r07-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:06:00.000Z",
  "eventType": "START",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000007",
    "facets": {
      "jobDependencies": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/JobDependenciesRunFacet.json",
        "jobDependencies": [
          { "namespace": "ci", "name": "upstream_pipeline.extract" },
          { "namespace": "ci", "name": "upstream_pipeline.clean"   }
        ]
      }
    }
  },
  "job":  { "namespace": "ci", "name": "downstream_pipeline.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- ExtractionErrorRunFacet (on a FAIL event) --------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r08-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:07:00.000Z",
  "eventType": "FAIL",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000008",
    "facets": {
      "extractionError": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/ExtractionErrorRunFacet.json",
        "totalTasks":         3,
        "failedTasks":        1,
        "errors": [
          {
            "errorMessage": "Failed to parse CTE in subquery at line 42",
            "stackTrace":   "SqlParseException: ...",
            "task":         "parse_sql",
            "taskNumber":   2
          }
        ]
      }
    }
  },
  "job":  { "namespace": "trino", "name": "query_parser.run" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- ExecutionParametersRunFacet ----------------------------------------------
# Note: spec-standard facet (spec/facets/ExecutionParametersRunFacet.json) that
# is missing from RFC appendix A.3.2 / A.4.2 tables — see RFC Unresolved #D.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r09-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:08:00.000Z",
  "eventType": "COMPLETE",
  "run": {
    "runId": "55555555-0000-0000-0000-000000000009",
    "facets": {
      "executionParameters": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/ExecutionParametersRunFacet.json",
        "parameters": [
          { "name": "spark.sql.shuffle.partitions", "value": "200" },
          { "name": "spark.executor.memory",        "value": "4g"  }
        ]
      }
    }
  },
  "job":  { "namespace": "spark", "name": "etl.join" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- NominalTimeRunFacet with only nominalStartTime (nominalEndTime optional)
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r10-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:09:00.000Z",
  "eventType": "START",
  "run": {
    "runId": "55555555-0000-0000-0000-00000000000a",
    "facets": {
      "nominalTime": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/NominalTimeRunFacet.json",
        "nominalStartTime": "2026-04-14T00:00:00Z"
      }
    }
  },
  "job":  { "namespace": "scheduled", "name": "streaming_window.aggregate" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- ParentRunFacet with a grandparent (`parent.root` chain) ------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f05-r11-run_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T15:10:00.000Z",
  "eventType": "START",
  "run": {
    "runId": "55555555-0000-0000-0000-00000000000b",
    "facets": {
      "parent": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/ParentRunFacet.json",
        "run":  { "runId": "11111111-2222-3333-4444-555555555555" },
        "job":  { "namespace": "ci", "name": "parent_pipeline.orchestrator" },
        "root": {
          "run": { "runId": "00000000-1111-2222-3333-444444444444" },
          "job": { "namespace": "ci", "name": "grandparent_pipeline.schedule" }
        }
      }
    }
  },
  "job":  { "namespace": "ci", "name": "child_pipeline.child_task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200
