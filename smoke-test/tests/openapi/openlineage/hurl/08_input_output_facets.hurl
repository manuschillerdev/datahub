# Input/output dataset facets — InputStatistics, DataQualityMetrics,
# OutputStatistics, DataQualityAssertions.
# Spec: OpenLineage/spec/facets/*Input*/*Output*Facet.json.
# RFC appendix A.5, A.6.

# --- OutputStatisticsOutputDatasetFacet ---------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r01-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:00.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000001" },
  "job":  { "namespace": "ci", "name": "stats_pipeline.write" },
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
          "rowCount": 152437,
          "size":     8421376
        }
      }
    }
  ]
}
HTTP 200

# --- InputStatisticsInputDatasetFacet -----------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r02-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:01.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000002" },
  "job":  { "namespace": "ci", "name": "stats_pipeline.read" },
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
          "rowCount": 1024000,
          "size":     67108864
        }
      }
    }
  ]
}
HTTP 200

# --- DataQualityMetricsInputDatasetFacet --------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r03-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:02.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000003" },
  "job":  { "namespace": "ci", "name": "dq_pipeline.profile" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    {
      "namespace": "postgres://db.example.com:5432/raw",
      "name": "users",
      "inputFacets": {
        "dataQualityMetrics": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DataQualityMetricsInputDatasetFacet.json",
          "rowCount": 50000,
          "bytes":    4194304,
          "columnMetrics": {
            "user_id":    { "nullCount": 0,    "distinctCount": 50000 },
            "first_name": { "nullCount": 12,   "distinctCount": 38420 }
          }
        }
      }
    }
  ]
}
HTTP 200

# --- DataQualityAssertionsDatasetFacet ----------------------------------------
# Spec: spec/facets/DataQualityAssertionsDatasetFacet.json — a list of
# boolean assertion results attached to an input dataset. This is the
# facet DataHub plans to route to its native `assertion` entity (RFC Future
# Work §1); for now the endpoint must accept the payload without erroring.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r04-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:03.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000004" },
  "job":  { "namespace": "ci", "name": "dq_pipeline.assert" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    {
      "namespace": "postgres://db.example.com:5432/raw",
      "name": "orders",
      "inputFacets": {
        "dataQualityAssertions": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DataQualityAssertionsDatasetFacet.json",
          "assertions": [
            { "assertion": "not_null",      "success": true,  "column": "order_id"    },
            { "assertion": "unique",        "success": true,  "column": "order_id"    },
            { "assertion": "min",           "success": false, "column": "total_cents" },
            { "assertion": "row_count > 0", "success": true                            }
          ]
        }
      }
    }
  ]
}
HTTP 200

# --- InputSubsetDatasetFacet — compare condition -----------------------------
# Spec: spec/facets/BaseSubsetDatasetFacet.json#/$defs/InputSubsetDatasetFacet
# (spec/tests/BaseSubsetDatasetFacet/1.json). A dataset facet family the
# original audit missed as "abstract"; it is not — the concrete forms are
# `InputSubsetDatasetFacet` / `OutputSubsetDatasetFacet`, attached via
# `inputFacets.subset` / `outputFacets.subset`.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r05-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:04.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000005" },
  "job":  { "namespace": "ci", "name": "subset_pipeline.filter_compare" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    {
      "namespace": "postgres://db.example.com:5432/raw",
      "name": "customers",
      "inputFacets": {
        "subset": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-0/BaseSubsetDatasetFacet.json#/$defs/InputSubsetDatasetFacet",
          "inputCondition": {
            "type": "compare",
            "left":  { "type": "field",   "field": "first_name" },
            "right": { "type": "literal", "value": "John" },
            "comparison": "EQUAL"
          }
        }
      }
    }
  ]
}
HTTP 200

# --- InputSubsetDatasetFacet — recursive binary AND --------------------------
# spec/tests/BaseSubsetDatasetFacet/2.json. Exercises discriminated-union
# recursion (binary containing two compare children).
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r06-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:05.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000006" },
  "job":  { "namespace": "ci", "name": "subset_pipeline.filter_binary" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    {
      "namespace": "postgres://db.example.com:5432/raw",
      "name": "customers",
      "inputFacets": {
        "subset": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-0/BaseSubsetDatasetFacet.json#/$defs/InputSubsetDatasetFacet",
          "inputCondition": {
            "type": "binary",
            "left": {
              "type": "compare",
              "left":  { "type": "field",   "field": "first_name" },
              "right": { "type": "literal", "value": "John" },
              "comparison": "EQUAL"
            },
            "right": {
              "type": "compare",
              "left":  { "type": "field",   "field": "last_name" },
              "right": { "type": "literal", "value": "Smith" },
              "comparison": "EQUAL"
            },
            "operator": "AND"
          }
        }
      }
    }
  ]
}
HTTP 200

# --- InputSubsetDatasetFacet — location list ---------------------------------
# spec/tests/BaseSubsetDatasetFacet/3.json.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r07-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:06.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000007" },
  "job":  { "namespace": "ci", "name": "subset_pipeline.filter_location" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    {
      "namespace": "s3://lake",
      "name": "partitioned/data",
      "inputFacets": {
        "subset": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-0/BaseSubsetDatasetFacet.json#/$defs/InputSubsetDatasetFacet",
          "inputCondition": {
            "type": "location",
            "locations": [
              "s3://some/bucket/location1",
              "s3://some/bucket/location2",
              "s3://some/bucket/location3"
            ]
          }
        }
      }
    }
  ]
}
HTTP 200

# --- InputSubsetDatasetFacet — partition list with optional identifier ------
# spec/tests/BaseSubsetDatasetFacet/4.json. Second partition omits the
# optional `identifier` field — tests optional-field handling inside the
# discriminated-union branch.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r08-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:07.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000008" },
  "job":  { "namespace": "ci", "name": "subset_pipeline.filter_partition" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    {
      "namespace": "hive://metastore.example.com:9083",
      "name": "warehouse.events_partitioned",
      "inputFacets": {
        "subset": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-0/BaseSubsetDatasetFacet.json#/$defs/InputSubsetDatasetFacet",
          "inputCondition": {
            "type": "partition",
            "partitions": [
              {
                "identifier": "2024-10-15-PL",
                "dimensions": { "business_date": "2024-10-15", "country": "PL" }
              },
              {
                "dimensions": { "business_date": "2024-10-15", "country": "DE" }
              }
            ]
          }
        }
      }
    }
  ]
}
HTTP 200

# --- OutputSubsetDatasetFacet — symmetric check -------------------------------
# Spec defines a sibling `OutputSubsetDatasetFacet` applied via
# `outputFacets.subset`. Same shape as the input form with `outputCondition`
# in place of `inputCondition`. Exercises the output-slot routing.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f08-r09-input_output_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T18:00:08.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "88888888-0000-0000-0000-000000000009" },
  "job":  { "namespace": "ci", "name": "subset_pipeline.filtered_output" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "filtered_customers",
      "outputFacets": {
        "subset": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-0/BaseSubsetDatasetFacet.json#/$defs/OutputSubsetDatasetFacet",
          "outputCondition": {
            "type": "compare",
            "left":  { "type": "field",   "field": "active" },
            "right": { "type": "literal", "value": "true" },
            "comparison": "EQUAL"
          }
        }
      }
    }
  ]
}
HTTP 200
