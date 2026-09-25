# Imported from nordlb-kafka manual requests (pre-RFC, ~2025-08).
# Source: job_with_column_lineage.hurl
# Purpose: represent what a real user was sending to the endpoint.

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/legacy-r02-column_lineage
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventType": "COMPLETE",
  "eventTime": "2025-08-15T12:00:00Z",
  "run": {
    "runId": "123e4567-e89b-21d3-a456-426614174000"
  },
  "job": {
    "namespace": "open_lineage_examples",
    "name": "example-job",
    "facets": {
      "orchestrator": {
        "_producer": "https://example.com",
        "_schemaURL": "https://openlineage.io/spec/1-0-2/OpenLineage.json#/$defs/OrchestratorJobFacet",
        "orchestrator": "custom-orchestrator"
      }
    }
  },
  "inputs": [
    {
      "namespace": "open_lineage_examples",
      "name": "source_table",
      "facets": {
        "schema": {
          "_producer": "https://example.com",
          "_schemaURL": "https://example.com/schema",
          "fields": [
            {
              "name": "col_a",
              "type": "STRING"
            },
            {
              "name": "col_b",
              "type": "INT"
            }
          ]
        }
      }
    }
  ],
  "outputs": [
    {
      "namespace": "open_lineage_examples",
      "name": "target_table",
      "facets": {
        "schema": {
          "_producer": "https://example.com",
          "_schemaURL": "https://example.com/schema",
          "fields": [
            {
              "name": "new_col_a",
              "type": "STRING"
            },
            {
              "name": "new_col_b",
              "type": "INT"
            }
          ]
        },
        "columnLineage": {
          "_producer": "https://example.com",
          "_schemaURL": "https://example.com/columnLineageSchema",
          "fields": {
            "new_col_a": {
              "inputFields": [
                {
                  "namespace": "open_lineage_examples",
                  "name": "source_table",
                  "field": "col_a"
                }
              ]
            },
            "new_col_b": {
              "inputFields": [
                {
                  "namespace": "open_lineage_examples",
                  "name": "source_table",
                  "field": "col_b"
                }
              ]
            }
          }
        }
      }
    }
  ],
  "producer": "https://github.com/OpenLineage/OpenLineage/evaluation/openlineage-examples",
  "schemaURL": "https://openlineage.io/spec/1-0-2/OpenLineage.json"
}
HTTP 200