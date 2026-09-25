# Imported from nordlb-kafka manual requests (pre-RFC, ~2025-08).
# Source: job_with_tags.hurl
# Purpose: represent what a real user was sending to the endpoint.

# tags are currently ignored by datahub, see: https://github.com/datahub-project/datahub/issues/14458
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/legacy-r05-tags
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2025-08-14T10:10:22.000Z",
  "eventType": "COMPLETE",
  "producer": "https://github.com/OpenLineage/OpenLineage/evaluation/openlineage-examples",
  "run": {
    "runId": "f50a8e01-bc8c-d4d2-9fff-0c7b7810716b"
  },
  "job": {
    "namespace": "open_lineage_examples",
    "name": "minimal_job_with_tags",
    "facets": {
      "orchestrator": {
        "_producer": "https://github.com/OpenLineage/OpenLineage",
        "_schemaURL": "https://openlineage.io/spec/1-0-2/OpenLineage.json#/definitions/OrchestratorJobFacet",
        "name": "minimal_job"
      },
      "tags": {
        "_producer": "https://github.com/OpenLineage/OpenLineage",
        "_schemaURL": "https://openlineage.io/spec/1-0-0/OpenLineage.json#/definitions/TagsJobFacet",
        "tags": [
          {
            "key": "environment",
            "value": "production",
            "source": "CONFIG"
          },
          {
            "key": "team",
            "value": "data-engineering",
            "source": "CONFIG"
          }
        ]
      }
    }
  },
  "outputs": []
}
HTTP 200