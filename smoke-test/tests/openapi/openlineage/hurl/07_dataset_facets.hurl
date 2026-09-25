# Standard dataset facets — Schema, Datasource, ColumnLineage (1.0 + 1.2),
# Documentation, Symlinks, Ownership, LifecycleStateChange (all enum values),
# DatasetVersion, TagsDataset, DatasetType, Catalog, Storage, Hierarchy.
# Spec: OpenLineage/spec/facets/*DatasetFacet.json.
# RFC appendix A.4.

# --- SchemaDatasetFacet (with nested struct fields) ---------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r01-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:00.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000001" },
  "job":  { "namespace": "ci", "name": "schema_pipeline.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432",
      "name": "warehouse.events",
      "facets": {
        "schema": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-1/SchemaDatasetFacet.json",
          "fields": [
            { "name": "event_id",   "type": "string", "description": "Primary key" },
            { "name": "event_time", "type": "timestamp" },
            {
              "name": "payload",
              "type": "struct",
              "fields": [
                { "name": "user_id", "type": "string" },
                { "name": "action",  "type": "string" }
              ]
            }
          ]
        }
      }
    }
  ]
}
HTTP 200

# --- DatasourceDatasetFacet ---------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r02-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:01.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000002" },
  "job":  { "namespace": "ci", "name": "datasource_pipeline.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "events",
      "facets": {
        "dataSource": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-1/DatasourceDatasetFacet.json",
          "name": "postgres-warehouse",
          "uri":  "postgres://db.example.com:5432/warehouse"
        }
      }
    }
  ]
}
HTTP 200

# --- ColumnLineageDatasetFacet ------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r03-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:02.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000003" },
  "job":  { "namespace": "ci", "name": "column_lineage_pipeline.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs": [
    { "namespace": "postgres://db.example.com:5432/raw", "name": "users" }
  ],
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "user_summary",
      "facets": {
        "columnLineage": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-2-0/ColumnLineageDatasetFacet.json",
          "fields": {
            "full_name": {
              "inputFields": [
                { "namespace": "postgres://db.example.com:5432/raw", "name": "users", "field": "first_name", "transformations": [ { "type": "DIRECT", "subtype": "IDENTITY", "description": "concat", "masking": false } ] },
                { "namespace": "postgres://db.example.com:5432/raw", "name": "users", "field": "last_name",  "transformations": [ { "type": "DIRECT", "subtype": "IDENTITY", "description": "concat", "masking": false } ] }
              ]
            },
            "user_age": {
              "inputFields": [
                { "namespace": "postgres://db.example.com:5432/raw", "name": "users", "field": "birth_date", "transformations": [ { "type": "DIRECT", "subtype": "TRANSFORMATION", "description": "age from birth_date", "masking": false } ] }
              ]
            }
          }
        }
      }
    }
  ]
}
HTTP 200

# --- DocumentationDatasetFacet ------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r04-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:03.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000004" },
  "job":  { "namespace": "ci", "name": "documented_dataset.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "s3://my-bucket",
      "name": "datalake/curated/users",
      "facets": {
        "documentation": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DocumentationDatasetFacet.json",
          "description": "Curated user records, deduplicated and joined with profile data."
        }
      }
    }
  ]
}
HTTP 200

# --- SymlinksDatasetFacet (Hive ↔ Iceberg cross-platform aliases) -------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r05-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:04.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000005" },
  "job":  { "namespace": "ci", "name": "symlink_pipeline.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "s3://my-bucket/warehouse",
      "name": "events",
      "facets": {
        "symlinks": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/SymlinksDatasetFacet.json",
          "identifiers": [
            { "namespace": "hive://metastore.example.com:9083", "name": "warehouse.events", "type": "TABLE" },
            { "namespace": "iceberg://catalog.example.com",      "name": "warehouse.events", "type": "TABLE" }
          ]
        }
      }
    }
  ]
}
HTTP 200

# --- OwnershipDatasetFacet ----------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r06-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:05.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000006" },
  "job":  { "namespace": "ci", "name": "owned_dataset.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "owned_table",
      "facets": {
        "ownership": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/OwnershipDatasetFacet.json",
          "owners": [ { "name": "data-platform-team", "type": "MAINTAINER" } ]
        }
      }
    }
  ]
}
HTTP 200

# --- LifecycleStateChangeDatasetFacet (DROP) ----------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r07-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:06.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000007" },
  "job":  { "namespace": "ci", "name": "drop_pipeline.cleanup" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "old_table",
      "facets": {
        "lifecycleStateChange": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/LifecycleStateChangeDatasetFacet.json",
          "lifecycleStateChange": "DROP"
        }
      }
    }
  ]
}
HTTP 200

# --- DatasetVersionDatasetFacet -----------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r08-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:07.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000008" },
  "job":  { "namespace": "ci", "name": "iceberg_pipeline.append" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "iceberg://catalog.example.com",
      "name": "warehouse.versioned_events",
      "facets": {
        "version": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DatasetVersionDatasetFacet.json",
          "datasetVersion": "snapshot-7895432109876543210"
        }
      }
    }
  ]
}
HTTP 200

# --- TagsDatasetFacet ---------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r09-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:08.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000009" },
  "job":  { "namespace": "ci", "name": "tagged_dataset.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "tagged_events",
      "facets": {
        "tags": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/TagsDatasetFacet.json",
          "tags": [
            { "key": "pii",         "value": "true",         "source": "USER" },
            { "key": "retention",   "value": "90d",          "source": "CONFIG" }
          ]
        }
      }
    }
  ]
}
HTTP 200

# --- DatasetTypeDatasetFacet --------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r10-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:09.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-00000000000a" },
  "job":  { "namespace": "ci", "name": "typed_dataset.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "iceberg://catalog.example.com",
      "name": "warehouse.fact_orders",
      "facets": {
        "datasetType": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/DatasetTypeDatasetFacet.json",
          "datasetType": "TABLE",
          "subType":     "ICEBERG"
        }
      }
    }
  ]
}
HTTP 200

# --- CatalogDatasetFacet ------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r11-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:10.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-00000000000b" },
  "job":  { "namespace": "ci", "name": "catalog_dataset.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "iceberg://catalog.example.com",
      "name": "warehouse.cataloged_events",
      "facets": {
        "catalog": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/CatalogDatasetFacet.json",
          "name":          "glue",
          "framework":     "iceberg",
          "type":          "hive",
          "metadataUri":   "thrift://metastore.example.com:9083",
          "warehouseUri":  "s3://warehouse/"
        }
      }
    }
  ]
}
HTTP 200

# --- StorageDatasetFacet ------------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r12-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:11.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-00000000000c" },
  "job":  { "namespace": "ci", "name": "storage_dataset.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "s3://warehouse",
      "name": "events.parquet",
      "facets": {
        "storage": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/StorageDatasetFacet.json",
          "storageLayer": "s3",
          "fileFormat":   "parquet"
        }
      }
    }
  ]
}
HTTP 200

# --- HierarchyDatasetFacet ----------------------------------------------------
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r13-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:12.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-00000000000d" },
  "job":  { "namespace": "ci", "name": "hierarchy_dataset.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "snowflake://acct.snowflakecomputing.com",
      "name": "PROD_DB.ANALYTICS.DAILY_METRICS",
      "facets": {
        "hierarchy": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/HierarchyDatasetFacet.json",
          "hierarchy": [
            { "label": "database", "value": "PROD_DB" },
            { "label": "schema",   "value": "ANALYTICS" },
            { "label": "table",    "value": "DAILY_METRICS" }
          ]
        }
      }
    }
  ]
}
HTTP 200

# --- LifecycleStateChangeDatasetFacet — every enum value ---------------------
# Spec enum: ALTER / CREATE / DROP / OVERWRITE / RENAME / TRUNCATE. DROP is
# already covered above; exercise the remaining five.

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r14-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:13.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-00000000000e" },
  "job":  { "namespace": "ci", "name": "lifecycle.create" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "newly_created_table",
      "facets": {
        "lifecycleStateChange": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/LifecycleStateChangeDatasetFacet.json",
          "lifecycleStateChange": "CREATE"
        }
      }
    }
  ]
}
HTTP 200

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r15-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:14.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-00000000000f" },
  "job":  { "namespace": "ci", "name": "lifecycle.alter" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "altered_table",
      "facets": {
        "lifecycleStateChange": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/LifecycleStateChangeDatasetFacet.json",
          "lifecycleStateChange": "ALTER"
        }
      }
    }
  ]
}
HTTP 200

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r16-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:15.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000010" },
  "job":  { "namespace": "ci", "name": "lifecycle.rename" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "renamed_table",
      "facets": {
        "lifecycleStateChange": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/LifecycleStateChangeDatasetFacet.json",
          "lifecycleStateChange": "RENAME",
          "previousIdentifier": {
            "namespace": "postgres://db.example.com:5432/warehouse",
            "name":      "old_table_name"
          }
        }
      }
    }
  ]
}
HTTP 200

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r17-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:16.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000011" },
  "job":  { "namespace": "ci", "name": "lifecycle.overwrite" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "overwritten_table",
      "facets": {
        "lifecycleStateChange": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/LifecycleStateChangeDatasetFacet.json",
          "lifecycleStateChange": "OVERWRITE"
        }
      }
    }
  ]
}
HTTP 200

POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r18-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:17.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000012" },
  "job":  { "namespace": "ci", "name": "lifecycle.truncate" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "truncated_table",
      "facets": {
        "lifecycleStateChange": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/LifecycleStateChangeDatasetFacet.json",
          "lifecycleStateChange": "TRUNCATE"
        }
      }
    }
  ]
}
HTTP 200

# --- ColumnLineageDatasetFacet 1.0 form (no `transformations[]`) -------------
# Pre-1.2 producers emit flat inputFields without the transformations array.
# Lifted from legacy/99_r02-column_lineage.hurl so the canonical suite covers it.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r19-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:18.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000013" },
  "job":  { "namespace": "ci", "name": "column_lineage_10.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs":  [ { "namespace": "postgres://db:5432/raw", "name": "users" } ],
  "outputs": [
    {
      "namespace": "postgres://db:5432/warehouse",
      "name": "user_v1",
      "facets": {
        "columnLineage": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-0-0/ColumnLineageDatasetFacet.json",
          "fields": {
            "full_name": {
              "inputFields": [
                { "namespace": "postgres://db:5432/raw", "name": "users", "field": "first_name" },
                { "namespace": "postgres://db:5432/raw", "name": "users", "field": "last_name"  }
              ]
            }
          }
        }
      }
    }
  ]
}
HTTP 200

# --- SchemaDatasetFacet with uppercase OpenLineage types ----------------------
# Spec uses lowercase convention (`string`, `int`) but some producers emit
# uppercase. RFC A.4.4 calls out the case-handling bug; this fixture pins the
# expected post-fix behavior: HTTP 200, facet accepted.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r20-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:19.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000014" },
  "job":  { "namespace": "ci", "name": "uppercase_schema.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "postgres://db.example.com:5432/warehouse",
      "name": "upper_case_events",
      "facets": {
        "schema": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-1/SchemaDatasetFacet.json",
          "fields": [
            { "name": "event_id",  "type": "STRING" },
            { "name": "user_id",   "type": "INT"    },
            { "name": "amount",    "type": "DECIMAL" },
            { "name": "created",   "type": "TIMESTAMP" }
          ]
        }
      }
    }
  ]
}
HTTP 200

# --- SchemaDatasetFacet with rich field types --------------------------------
# Lifted from spec/tests/SchemaDatasetFacet/1.json. Exercises the complex-type
# branches the simple-struct fixture in r01 does not reach: `int64`, `map` with
# nested key/value, `union` with `_0` / `_1` branches, and `array` with
# `_element`. A parser that hardcodes `struct` and primitive types will fail
# this one.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r21-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:20.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000015" },
  "job":  { "namespace": "ci", "name": "rich_schema.load" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "outputs": [
    {
      "namespace": "s3://warehouse",
      "name": "people_rich",
      "facets": {
        "schema": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/blob/v1-0-0/client",
          "_schemaURL": "https://openlineage.io/spec/facets/1-1-1/SchemaDatasetFacet.json",
          "fields": [
            { "name": "user_id",         "type": "int64"  },
            { "name": "counterparty_id", "type": "int64"  },
            { "name": "currency",        "type": "object" },
            { "name": "amount",          "type": "int64"  },
            {
              "name": "phones", "type": "array", "description": "List of phone numbers",
              "fields": [ { "name": "_element", "type": "string", "description": "Phone number" } ]
            },
            {
              "name": "addresses", "type": "struct", "description": "Customer addresses",
              "fields": [
                { "name": "type",    "type": "string" },
                { "name": "country", "type": "string" },
                { "name": "zip",     "type": "string" },
                { "name": "state",   "type": "string" },
                { "name": "street",  "type": "string" }
              ]
            },
            {
              "name": "custom_properties", "type": "map",
              "fields": [
                { "name": "key",   "type": "string" },
                {
                  "name": "value", "type": "union",
                  "fields": [
                    { "name": "_0", "type": "string" },
                    { "name": "_1", "type": "int64"  }
                  ]
                }
              ]
            }
          ]
        }
      }
    }
  ]
}
HTTP 200

# --- ColumnLineageDatasetFacet with dataset-level `dataset[]` array ----------
# Lifted from spec/tests/ColumnLineageDatasetFacet/2.json. The 1.2 spec adds
# a top-level `dataset[]` array (alongside the existing per-field map) for
# INDIRECT lineage — e.g. a column used in SORT or FILTER that influences
# *which* output rows exist but not *which* columns. An ingestion path that
# only walks `fields[*].inputFields` drops these entirely.
POST {{host}}/openapi/openlineage/api/v1/lineage
User-Agent: hurl/{{run_id}}/f07-r22-dataset_facets
Content-Type: application/json
Authorization: Bearer {{token}}
{
  "eventTime": "2026-04-14T17:00:21.000Z",
  "eventType": "COMPLETE",
  "run":  { "runId": "77777777-0000-0000-0000-000000000016" },
  "job":  { "namespace": "spark", "name": "column_lineage_indirect.transform" },
  "producer":  "https://github.com/OpenLineage/OpenLineage/tree/1.23.0-SNAPSHOT/integration/spark",
  "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
  "inputs":  [ { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people" } ],
  "outputs": [
    {
      "namespace": "s3://test-bucket",
      "name": "/iceberg_warehouse/some-database/people_summary",
      "facets": {
        "columnLineage": {
          "_producer":  "https://github.com/OpenLineage/OpenLineage/tree/1.23.0-SNAPSHOT/integration/spark",
          "_schemaURL": "https://openlineage.io/spec/facets/1-2-0/ColumnLineageDatasetFacet.json#/$defs/ColumnLineageDatasetFacet",
          "fields": {
            "id":          { "inputFields": [ { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people", "field": "id",         "transformations": [ { "type": "DIRECT", "subtype": "IDENTITY",       "description": "", "masking": false } ] } ] },
            "firstName":   { "inputFields": [ { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people", "field": "first_name", "transformations": [ { "type": "DIRECT", "subtype": "IDENTITY",       "description": "", "masking": false } ] } ] },
            "lastName":    { "inputFields": [ { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people", "field": "last_name",  "transformations": [ { "type": "DIRECT", "subtype": "IDENTITY",       "description": "", "masking": false } ] } ] },
            "ageNextYear": { "inputFields": [ { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people", "field": "age",        "transformations": [ { "type": "DIRECT", "subtype": "TRANSFORMATION", "description": "", "masking": false } ] } ] }
          },
          "dataset": [
            { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people", "field": "last_name",  "transformations": [ { "type": "INDIRECT", "subtype": "SORT",   "description": "", "masking": false } ] },
            { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people", "field": "first_name", "transformations": [ { "type": "INDIRECT", "subtype": "SORT",   "description": "", "masking": false } ] },
            { "namespace": "s3://test-bucket", "name": "/iceberg_warehouse/some-database/people", "field": "age",        "transformations": [ { "type": "INDIRECT", "subtype": "FILTER", "description": "", "masking": false } ] }
          ]
        }
      }
    }
  ]
}
HTTP 200
