# Imported from nordlb-kafka manual requests (pre-RFC, ~2025-08).
# Source: job_with_documentation.hurl
# Purpose: represent what a real user was sending to the endpoint.

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/legacy-r03-documentation
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2025-08-14T10:10:22.000Z",
  "eventType": "COMPLETE",
  "producer": "https://github.com/OpenLineage/OpenLineage/evaluation/openlineage-examples",
  "run": {
    "runId": "f50a8e01-bc8c-4d42-9fff-0c7b7810716d"
  },
  "job": {
    "namespace": "open_lineage_examples",
    "name": "minimal_job_with_documentation",
    "facets": {
      "orchestrator": {
        "_producer": "https://github.com/OpenLineage/OpenLineage",
        "_schemaURL": "https://openlineage.io/spec/1-0-2/OpenLineage.json#/definitions/OrchestratorJobFacet",
        "name": "minimal_job"
      },
      "documentation": {
        "_producer": "https://github.com/OpenLineage/OpenLineage",
        "_schemaURL": "https://openlineage.io/spec/1-0-2/OpenLineage.json#/definitions/DocumentationJobFacet",
        "description": "This is a brief description of the minimal job. It demonstrates how to add metadata to an OpenLineage payload. zz"
      }
    }
  },
  "outputs": []
}
HTTP 200