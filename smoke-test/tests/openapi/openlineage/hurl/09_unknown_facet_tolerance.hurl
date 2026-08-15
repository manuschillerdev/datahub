# Unknown / future / vendor-specific facets must be tolerated.
# Spec: OpenLineage allows producers to attach arbitrary facets via
# `additionalProperties` on Run/Job/Dataset.
# RFC §"Detailed design" / §7 — log at DEBUG, never 500.

# --- Unknown run facet --------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r01-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:00.000Z",
  "eventType": "COMPLETE",
  "run": {
    "runId": "99999999-0000-0000-0000-000000000001",
    "facets": {
      "vendorSpecificFacet_v42": {
        "_producer":  "https://example.com/vendor",
        "_schemaURL": "https://example.com/spec/vendor/v42/Facet.json",
        "internalRunHandle": "run-9876",
        "qosClass": "premium",
        "shardCount": 16
      }
    }
  },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Unknown job facet alongside known DocumentationJobFacet ------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r02-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:01.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "99999999-0000-0000-0000-000000000002" },
  "job": {
    "namespace": "ns",
    "name": "flow.task",
    "facets": {
      "documentation": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DocumentationJobFacet.json",
        "description": "Known facet that should still be persisted."
      },
      "futureJobFacet_v999": {
        "_producer":  "https://example.com/future",
        "_schemaURL": "https://example.com/spec/v999/Facet.json",
        "experimentalField": true,
        "nestedThing": { "a": 1, "b": [ "x", "y" ] }
      }
    }
  },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200

# --- Unknown dataset facet on an output ---------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r03-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:02.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "99999999-0000-0000-0000-000000000003" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "s3://my-bucket",
      "name": "data/output",
      "facets": {
        "vendorDatasetFacet": {
          "_producer":  "https://example.com/vendor",
          "_schemaURL": "https://example.com/spec/vendor/Dataset.json",
          "internalCatalogId": "cat-789"
        }
      }
    }
  ]
}
HTTP 200

# --- Unknown inputFacets slot on an InputDataset ------------------------------
# The inputFacets map has `additionalProperties: true` per the spec, so
# vendors can attach arbitrary facets here. Mixed with a known
# InputStatisticsInputDatasetFacet so routing of the known facet is preserved.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r04-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:03.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "99999999-0000-0000-0000-000000000004" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    {
      "namespace": "postgres://db.example.com:5432/raw",
      "name": "raw_events",
      "inputFacets": {
        "inputStatistics": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/InputStatisticsInputDatasetFacet.json",
          "rowCount": 1000,
          "size":     65536
        },
        "vendorInputFacet": {
          "_producer":  "https://example.com/vendor",
          "_schemaURL": "https://example.com/spec/vendor/InputFacet.json",
          "partitionsScanned": 7,
          "cacheHitRate":      0.82
        }
      }
    }
  ]
}
HTTP 200

# --- Unknown outputFacets slot on an OutputDataset ----------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r05-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:04.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "99999999-0000-0000-0000-000000000005" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "stats_table",
      "outputFacets": {
        "outputStatistics": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/OutputStatisticsOutputDatasetFacet.json",
          "rowCount": 2048,
          "size":     131072
        },
        "vendorOutputFacet": {
          "_producer":  "https://example.com/vendor",
          "_schemaURL": "https://example.com/spec/vendor/OutputFacet.json",
          "compactionTriggered": true,
          "shardCount":          32
        }
      }
    }
  ]
}
HTTP 200

# --- Unknown facet on DatasetEvent.dataset.facets -----------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r06-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:05.000Z",
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/DatasetEvent",
  "dataset": {
    "namespace": "s3://my-bucket",
    "name": "vendor_facet_dataset",
    "facets": {
      "vendorStandaloneFacet": {
        "_producer":  "https://example.com/vendor",
        "_schemaURL": "https://example.com/spec/vendor/StandaloneDatasetFacet.json",
        "futureField": "future-value",
        "futureList": [ 1, 2, 3 ]
      }
    }
  }
}
HTTP 200

# --- Unknown top-level envelope field -----------------------------------------
# `additionalProperties` on the envelope is unset in the OL JSON Schema, which
# defaults to `true`. A future spec version adding a new top-level envelope
# field (or a vendor emitting an extension) must pass through the validator
# without rejection. This fixture sends a `vendorExtension` object alongside
# the standard RunEvent fields. Also mirrors the OL-shipped test fixture
# `spec/tests/example_full_event.json`, which carries an extra top-level
# `dataset` object on a RunEvent.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r07-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:06.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "99999999-0000-0000-0000-000000000007" },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "vendorExtension": {
    "region": "eu-central-1",
    "tenantId": "acme-42",
    "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  }
}
HTTP 200

# --- Unknown nested field on a standard facet --------------------------------
# A newer-minor facet version may add optional fields. The envelope validator
# doesn't descend into facets and the typed deserializer must tolerate unknown
# properties on known facets (Jackson `FAIL_ON_UNKNOWN_PROPERTIES = false`).
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f09-r08-unknown_facet_tolerance
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T19:00:07.000Z",
  "eventType": "COMPLETE",
  "run":  {
    "runId": "99999999-0000-0000-0000-000000000008",
    "facets": {
      "nominalTime": {
        "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
        "_schemaURL": "https://openlineage.io/spec/facets/2-0-0/NominalTimeRunFacet.json",
        "nominalStartTime": "2026-04-14T00:00:00Z",
        "nominalEndTime":   "2026-04-15T00:00:00Z",
        "futureNominalField": "added-in-2-0-0"
      }
    }
  },
  "job":  { "namespace": "ns", "name": "flow.task" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent"
}
HTTP 200
