# Imported from nordlb-kafka manual requests (pre-RFC, ~2025-08).
# Source: job_with_ownerships.hurl
# Purpose: represent what a real user was sending to the endpoint.

# ownerships are currently ignored by datahub, see: https://github.com/datahub-project/datahub/issues/14458
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/legacy-r04-ownerships
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2025-08-14T10:10:22.000Z",
  "eventType": "COMPLETE",
  "producer": "https://github.com/OpenLineage/OpenLineage/evaluation/openlineage-examples",
  "run": {
    "runId": "f50a8e01-bc8c-4d42-9fff-0c7b7810716a"
  },
  "job": {
    "namespace": "open_lineage_examples",
    "name": "minimal_job_with_ownerships",
    "facets": {
      "orchestrator": {
        "_producer": "https://github.com/OpenLineage/OpenLineage",
        "_schemaURL": "https://openlineage.io/spec/1-0-2/OpenLineage.json#/definitions/OrchestratorJobFacet",
        "name": "minimal_job"
      },
      "ownership": {
        "_producer": "https://github.com/OpenLineage/OpenLineage",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-1/OwnershipJobFacet.json#/$defs/OwnershipJobFacet",
        "owners": [
          {
            "name": "jdoe",
            "type": "DEVELOPER"
          },
          {
            "name": "DataHub",
            "type": "DEVELOPER"
          },
          {
            "name": "datahub",
            "type": "DEVELOPER"
          }
        ]
      }
    }
  },
  "outputs": []
}
HTTP 200