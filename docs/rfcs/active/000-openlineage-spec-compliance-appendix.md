# Appendix — OpenLineage endpoint: methodology, test suite, mapping, gaps

Companion to [`000-openlineage-spec-compliance.md`](./000-openlineage-spec-compliance.md).

File and line references are against `master` at commit `7ed8710c65`.

## Sections

- [A.1 Methodology](#a1-methodology)
- [A.2 Test suite overview](#a2-test-suite-overview)
- [A.3 OpenLineage ↔ DataHub ↔ Marquez mapping](#a3-openlineage--datahub--marquez-mapping)
- [A.4 Status quo and gaps](#a4-status-quo-and-gaps)
- [A.5 OpenAPI contract drift](#a5-openapi-contract-drift)
- [A.6 Milestone roll-up](#a6-milestone-roll-up)
- [A.7 Linked issues and PRs](#a7-linked-issues-and-prs)

---

## A.1 Methodology

Findings are obtained through three complementary techniques. Every row in the
status tables in §A.4 is backed by at least one of them.

### A.1.1 Source-level audit

Full read of the four files that implement the endpoint:

- `metadata-service/openapi-servlet/src/main/java/io/datahubproject/openapi/openlineage/controller/LineageApiImpl.java`
- `metadata-service/openapi-servlet/src/main/java/io/datahubproject/openapi/openlineage/mapping/RunEventMapper.java`
- `metadata-integration/java/openlineage-converter/src/main/java/io/datahubproject/openlineage/converter/OpenLineageToDataHub.java` (1373 lines)
- `metadata-service/openapi-servlet/src/main/resources/openlineage/openlineage.json` (412 lines)

Each of the 32 standard OpenLineage facets is located in the converter by
name-based search and its call site is traced. Anything reachable only via
untyped JSON (`RunFacet.getAdditionalProperties().get(...)`) is noted as
custom-facet handling and listed separately in §A.4.7.

### A.1.2 Executable end-to-end suite

The Hurl suite under `smoke-test/tests/openapi/openlineage/hurl/` exercises
the live endpoint. Every request carries a unique `User-Agent` header of the
form `hurl/<run_id>/f<NN>-r<MM>-<slug>`. DataHub's `RequestContext` logs the
user-agent verbatim on every request, so the GMS container log can be sliced
per request for exact MCP attribution.

`run.sh` generates a fresh `run_id` per invocation, captures a log mark, runs
hurl, then filters `docker logs --since <mark>` and invokes `parse_gms.py`.
The parser walks each Jetty worker thread sequentially, splits at every
`LineageApiImpl:59 - Received lineage event:` marker, attaches the
`User-Agent` from the block's `RequestContext` line, and collects every
`LineageApiImpl:93 - Ingesting MCP:` line in the block. Output is a table of
`<UA tag> → <entity(aspect*changeType,…)>` rows, plus an aspect-total tally
keyed by `(entity type, aspect name, change type)`. Stale log entries from
prior runs cannot collide because their `user_agent` carries a different
`run_id`.

A two-back-to-back invocation of the same file yields two independent reports
with disjoint correlations; this confirms the correlation is robust under
concurrent runs and shared log buffers.

### A.1.3 Aspect-store verification

For every claim about "what was actually persisted", the DataHub OpenAPI v3
entity endpoint is queried directly:

```
GET /openapi/v3/entity/<entityType>/<encoded urn>?systemMetadata=false
```

This returns the authoritative aspect set for each URN and provides ground
truth independent of log parsing. The responses confirm:

- Which aspects are present on each entity.
- The shape of each written aspect, including typed field values.
- Whether a referenced `dataPlatform` URN actually exists as an entity (`404`
  indicates a ghost reference written by the converter without a backing
  DataHub `dataPlatform` entity).

---

## A.2 Test suite overview

Location: `smoke-test/tests/openapi/openlineage/hurl/`.

### A.2.1 Layout

```
hurl/
├── README.md                                    suite guide and coverage statement
├── vars.env                                     host + token variables
├── run.sh                                       runner: generates run_id, invokes hurl, calls parse_gms.py
├── parse_gms.py                                 log attribution by User-Agent; PATCH vs UPSERT aware
├── 01_envelope_required_fields.hurl             every BaseEvent/Run/Job/Dataset required-field negative; unparseable body; wrong media type; type-mismatch negatives
├── 01_envelope_required_fields_workaround.hurl  pre-RFC variant with explicit eventType=COMPLETE (delete in dispatch-fix PR)
├── 02_event_types.hurl                          RunEvent / JobEvent / DatasetEvent dispatch + exclusion negatives + empty inputs/outputs + legacy 2-0-0 schemaURL
├── 03_run_state_transitions.hurl                every eventType enum value (START, RUNNING, COMPLETE, FAIL + ErrorMessage, ABORT, OTHER) + 3 enum negatives
├── 04_producer_uri.hurl                         canonical OL / Airflow / Trino / custom-github / non-github / ProcessingEngine-driven / arn: scheme + URI negatives
├── 05_run_facets.hurl                           every standard run facet: NominalTime (full + partial), Parent (with + without root/grandparent), ProcessingEngine, ExternalQuery, EnvironmentVariables, TagsRun, JobDependencies, ExtractionError, ExecutionParameters
├── 06_job_facets.hurl                           every standard job facet: Documentation, SourceCodeLocation, SourceCode, SQL, Ownership (full type enum), Tags, JobType (BATCH + STREAMING)
├── 07_dataset_facets.hurl                       every standard dataset facet: Schema (nested struct / upper-case / rich map+union+array), Datasource, ColumnLineage 1.0 + 1.2 + 1.2 dataset-level, Documentation, Symlinks, Ownership, LifecycleStateChange (all 6 enum values), Version, Tags, DatasetType, Catalog, Storage, Hierarchy
├── 08_input_output_facets.hurl                  OutputStatistics, InputStatistics, DataQualityMetrics, DataQualityAssertions, InputSubset (compare / binary-AND / location / partition), OutputSubset
├── 09_unknown_facet_tolerance.hurl              vendor facets on Run, Job, Dataset, inputFacets, outputFacets, DatasetEvent.dataset.facets; unknown top-level envelope field; unknown nested field on a known facet
├── 10_unicode_and_edge_cases.hurl               Unicode names, nanosecond precision, non-UTC offset, 3 naive-tz positives (ms / second / OL Python microsecond precision), 1 epoch-ms negative
├── 10_unicode_and_edge_cases_strict.hurl        spec-strict alternative to the naive-tz positives (HTTP 400). Excluded from the pytest runner by the `*_strict.hurl` filename convention.
└── legacy/                                      pre-RFC real-world requests, same correlation pipeline
    ├── 99_r01-minimal.hurl
    ├── 99_r02-column_lineage.hurl               uses older 1.0-form column lineage (no transformations[])
    ├── 99_r03-documentation.hurl
    ├── 99_r04-ownerships.hurl
    └── 99_r05-tags.hurl
```

Total: 116 requests (111 synthetic + 5 legacy), each tagged with a unique
`User-Agent`.

### A.2.2 Correlation semantics

| Signal | Source | Scope |
|---|---|---|
| `run_id` | generated by `run.sh` per invocation | partitions log lines across concurrent runs |
| `f<NN>-r<MM>-<slug>` | injected per request in each `.hurl` file | uniquely identifies one request within a run |
| `User-Agent: hurl/<run_id>/<tag>` | HTTP header sent by Hurl | logged by DataHub `RequestContext:118` |
| Jetty worker thread id | `[qtp<pool>-<id>]` in log lines | groups sequential activity within one request |

A request is **attributed** when its `User-Agent` header matches a
`RequestContext` log line within the same thread window as a `Received
lineage event` marker. A request is **pre-dispatch-rejected** when no
`Received lineage event` appears in the log — for example, when Jackson
rejects a timestamp before the controller runs. Both states are reported
unambiguously by `parse_gms.py`.

### A.2.3 Run output

`run.sh` emits:

1. Hurl's own per-file result (HTTP status assertions).
2. A per-request delta table: one row per `f<NN>-r<MM>-<slug>`, with
   HTTP/exception status and the list of entity/aspect pairs written for that
   request. PATCH MCPs are annotated `<aspect>*PATCH` so they are distinct
   from UPSERTs.
3. An aspect-total tally per `(entity, aspect, changeType)` for the whole
   run.

Example row from a full-suite run:

```
f07-r03-dataset_facets  ✔ 200 OK  dataFlow(dataFlowInfo,status) |
  dataJob(dataJobInfo,dataJobInputOutput*PATCH,status) |
  dataProcessInstance(dataProcessInstanceInput,dataProcessInstanceOutput,
    dataProcessInstanceProperties,dataProcessInstanceRelationships,
    dataProcessInstanceRunEvent) |
  dataset(datasetKey,status)
```

### A.2.4 Clean-slate option

`run.sh --reset` invokes `scripts/dev/datahub-dev.sh nuke --keep-data` before
the suite runs, producing a pristine aspect store for runs that must not
interact with prior state. Without `--reset`, isolation is provided by the
`run_id`-scoped `User-Agent` correlation; two back-to-back invocations
produce disjoint reports even on a shared aspect store.

### A.2.5 Coverage against the spec

| Spec area | Synthetic file | Legacy file | Notes |
|---|---|---|---|
| `BaseEvent` required fields | 01 | — | 5 requests |
| Event-type dispatch (`oneOf`) | 02 | 99/1, 99/2 | 3 synthetic + 2 legacy |
| `RunEvent.eventType` enum | 03 | — | 7 synthetic |
| Free-form `producer` URI | 04 | 99/* (all) | 6 synthetic + 5 legacy; legacy exercises `…/evaluation/openlineage-examples` |
| Run facets (4) | 05 | — | 4 synthetic |
| Job facets (7) | 06 | 99/3 (Documentation), 99/4 (Ownership), 99/5 (Tags) | 7 synthetic + 3 legacy |
| Dataset facets (8) | 07 | 99/2 (Schema × 2, ColumnLineage 1.0 form) | 8 synthetic + 1 legacy |
| Input / output facets (3) | 08 | — | 3 synthetic |
| Unknown-facet tolerance | 09 | — | 3 synthetic |
| Unicode, nanosecond, timezone edge cases | 10 | — | 4 synthetic |

Fixture payloads are oriented on the OpenLineage 2-0-2 core spec, the 32
standard facets under `OpenLineage/OpenLineage/spec/facets/`, and the Marquez
reference corpus at `api/src/test/resources/open_lineage/`.

---

## A.3 OpenLineage ↔ DataHub ↔ Marquez mapping

A cross-walk for each spec element. The **Marquez** column records what
Marquez persists (derived from `marquez.db.OpenLineageDao` and the row mappers
under `api/src/main/java/marquez/db/mappers/`). The **DataHub target** column
records what the converter should produce. Row-level implementation status is
in §A.4.

**Upstream home.** The OpenLineage project maintains a cross-consumer
compatibility repo at `github.com/OpenLineage/compatibility-tests` where
each consumer ships its own mapping in a standardized JSON format —
`consumer/consumers/<name>/mapping.json` with `mapped.core`,
`mapped.<FacetName>`, and `knownUnmapped` sections. Currently the repo
has one consumer entry (`dataplex`). This prose cross-walk is the
authoring form; the RFC's Future Work includes re-expressing it as
`consumer/consumers/datahub/mapping.json` and contributing it upstream so
DataHub joins the OL conformance matrix.

### A.3.1 Envelope

| OpenLineage element | Marquez | DataHub target |
|---|---|---|
| `RunEvent` | `runs` + `run_states` rows | `DataProcessInstance` MCPs + referenced `DataFlow`/`DataJob`/`Dataset` |
| `JobEvent` | `jobs` + `job_versions` rows, no run linkage | `DataFlow` + `DataJob` + `dataJobInputOutput` + referenced `Dataset` (no DPI) |
| `DatasetEvent` | `datasets` + `dataset_versions` rows, no job/run linkage | `Dataset` aspects only |
| `eventTime` | `run_states.transitioned_at` | `dataProcessInstanceRunEvent.timestampMillis` + `dataProcessInstanceProperties.created` |
| `producer` | `lineage_events.producer` (verbatim) | signal for orchestrator derivation |
| `schemaURL` | `lineage_events.schema_url` (verbatim) | not load-bearing; accepted as-is |
| `run.runId` | `runs.uuid` | `dataProcessInstance` URN |
| `job.{namespace,name}` | `jobs.namespace_name` + `jobs.name` | `dataFlowKey` + `dataJobKey` (via split-on-`.`) |
| `inputs[]` / `outputs[]` | `dataset_versions_io_mapping` rows | `dataJobInputOutput.inputDatasetEdges` / `outputDatasetEdges` |
| `eventType` enum | `run_states.state` | `dataProcessInstanceRunEvent.status` + `.result.type` |

### A.3.2 Run facets

| OpenLineage facet | Marquez persistence | DataHub target aspect |
|---|---|---|
| `NominalTimeRunFacet` | `run_args` promoted columns (`nominal_start_time`, `nominal_end_time`) | `dataProcessInstanceProperties.created` (nominal start) + custom property `nominalEndTime` |
| `ParentRunFacet` | `runs.parent_run_uuid` | `dataProcessInstanceRelationships.parentInstance` |
| `ErrorMessageRunFacet` | JSONB only (`run_facets`) | `dataProcessInstanceRunEvent` FAILURE + custom properties `errorMessage`, `programmingLanguage`, `stackTrace` |
| `ProcessingEngineRunFacet` | JSONB only | orchestrator-name input + `versionInfo.version` on DataFlow |
| `ExternalQueryRunFacet` | JSONB only | `operation.customProperties.externalQueryId` on outputs |
| `EnvironmentVariablesRunFacet` | JSONB only | `dataProcessInstanceProperties.customProperties` (prefixed `env.`) |
| `TagsRunFacet` | JSONB only | `globalTags` on parent DataJob |
| `JobDependenciesRunFacet` | JSONB only | `dataJobInputOutput.inputDatajobs` entries |
| `ExtractionErrorRunFacet` | JSONB only | `dataProcessInstanceRunEvent` FAILURE + custom property `extractionErrors` |

### A.3.3 Job facets

| OpenLineage facet | Marquez persistence | DataHub target aspect |
|---|---|---|
| `DocumentationJobFacet` | `jobs.description` promoted column | `dataJobInfo.description` |
| `SourceCodeLocationJobFacet` | `jobs.location` promoted column | `dataJobInfo.externalUrl` |
| `SourceCodeJobFacet` | JSONB only (`job_facets`) | `dataTransformLogic.transformations[].rawTransformation` |
| `SQLJobFacet` | JSONB only | `dataTransformLogic.transformations[].queryStatement` on DataJob + mirror to `operation.customProperties.queryStatement` on each output |
| `OwnershipJobFacet` | JSONB only | `ownership` on DataJob (OL `type` → DataHub `OwnershipType`) |
| `TagsJobFacet` | JSONB only | `globalTags` on DataJob |
| `JobTypeJobFacet` | JSONB only | `subTypes.typeNames[0] = jobType`; `processingType` → `dataJobInfo.type`; `integration` → DataPlatform override |

### A.3.4 Dataset facets

| OpenLineage facet | Marquez persistence | DataHub target aspect |
|---|---|---|
| `SchemaDatasetFacet` | `dataset_fields` rows | `schemaMetadata.fields` (recursive for nested structs) |
| `DatasourceDatasetFacet` | `sources.name` + `sources.uri` | `dataPlatformInstance.instance` + `datasetProperties.externalUrl` |
| `ColumnLineageDatasetFacet` | `column_lineage` table (one row per upstream field pair) | `upstreamLineage.fineGrainedLineages[]` on output Dataset |
| `OwnershipDatasetFacet` | JSONB only (`dataset_facets`) | `ownership` on Dataset |
| `LifecycleStateChangeDatasetFacet` | `datasets.is_deleted` (derived) | `status.removed = true` for DROP/TRUNCATE |
| `SymlinksDatasetFacet` | `dataset_symlinks` rows | `siblings.siblings[]` |
| `StorageDatasetFacet` | JSONB only | `datasetProperties.customProperties` (`storageLayer`, `fileFormat`) |
| `DatasetVersionDatasetFacet` | JSONB only | `versionProperties.version.versionTag` |
| `DocumentationDatasetFacet` | `datasets.description` promoted column | `datasetProperties.description` |
| `DatasetTypeDatasetFacet` | JSONB only | `subTypes.typeNames` |
| `CatalogDatasetFacet` | JSONB only | `dataPlatformInstance.instance` |
| `HierarchyDatasetFacet` | JSONB only | `container` aspect |
| `TagsDatasetFacet` | JSONB only | `globalTags` on Dataset |

### A.3.5 Input / output dataset facets

| OpenLineage facet | Marquez persistence | DataHub target aspect |
|---|---|---|
| `DataQualityMetricsInputDatasetFacet` | JSONB only (`input_dataset_facets`) | `datasetProfile` time-series MCP on the input |
| `InputStatisticsInputDatasetFacet` | JSONB only | `operation` on input, `customOperationType = READ` |
| `OutputStatisticsOutputDatasetFacet` | JSONB only (`output_dataset_facets`) | `operation` on output, `numAffectedRows = rowCount`, `numAffectedBytes = size` |
| `DataQualityAssertionsDatasetFacet` | JSONB only | `assertion` entity + `assertionRunEvent` per assertion |

### A.3.6 Storage-model note

Marquez retains the full raw payload of every facet as JSONB alongside any
promoted typed columns. Facets Marquez does not specifically understand are
still persisted and remain queryable. DataHub has no equivalent raw-event
store: facets the converter does not map are dropped. The unmapped-facet
debug log proposed in the RFC makes the drop observable.

---

## A.4 Status quo and gaps

Status legend: **✅** implemented and written to the target aspect.
**🟡** extracted but written to a divergent target, partial shape, or discarded
before persistence. **❌** not read by the converter.

Priority legend: **P0** baseline spec compliance. **P1** standard producer
coverage. **P2** quality/edge cases.

### A.4.1 Endpoint dispatch and envelope

| Element | Target | Prio | Status | Notes |
|---|---|---|---|---|
| `RunEvent` deserialization | `OpenLineageClientUtils.runEventFromJson` | P0 | ✅ | `LineageApiImpl.java:60` |
| `JobEvent` dispatch | Polymorphic deserializer | P0 | ❌ | Controller calls `runEventFromJson` unconditionally. Downstream NPE at `RunEvent.getRun().getFacets()`. Surfaces as #15196. |
| `DatasetEvent` dispatch | Polymorphic deserializer | P0 | ❌ | No code branch exists. |
| Free-form `producer` URI | Total orchestrator derivation | P0 | ❌ | `OpenLineageToDataHub.java:1275-1301`. Hard-coded regex + prefix allow-list throws `RuntimeException("Unable to determine orchestrator")` on unknown producers. Surfaces as #16961, #13011. |
| Orchestrator name for canonical OpenLineage producer URLs | Registered `dataPlatform` entity | P0 | ❌ | The regex `https://github.com/OpenLineage/OpenLineage/.*/(.*)$` captures the last path segment of the producer URL. `.../blob/v1-0-0/client` yields orchestrator `client`; `.../evaluation/openlineage-examples` yields `openlineage-examples`. Both resulting `urn:li:dataPlatform:*` URNs return `404` from the entity endpoint — ghost references written into `dataFlowKey.orchestrator` and `dataPlatformInstance.platform`. |
| `dataJobInfo.type` | Derived from `JobTypeJobFacet` | P0 | 🟡 | Currently set from the orchestrator name (e.g. `{"string":"client"}` for canonical-OL jobs). `JobTypeJobFacet.processingType`/`.jobType` is not consulted. |
| `RunEvent.eventType` enum mapping | `dataProcessInstanceRunEvent.status` + `.result.type` | P0 | 🟡 | `:1193-1237`. `START`/`RUNNING`/`COMPLETE`/`FAIL`/`ABORT` map correctly. `OTHER` sets `result.type = RunResultType.$UNKNOWN`, a Pegasus sentinel that fails aspect validation (`/result/type :: "$UNKNOWN" is not an enum symbol`). Missing `eventType` (optional per spec) NPEs on `.ordinal()` before reaching the switch. |
| `RunEvent.eventTime` | DPI `created` + run-event `timestampMillis` | P0 | ✅ | `:1077-1081`, `:1203` |
| `Run.runId` | `dataProcessInstanceKey` + properties | P0 | ✅ | `:1075` |
| `Job.{namespace,name}` | `dataJobKey` + `dataFlowKey` via split-on-`.` | P0 | 🟡 | `getFlowUrn` at `:1248`. No-dot job names produce `flowId == taskId` (degenerate URN; functional but inconsistent). |
| `RunEvent.inputs[]` | `dataJobInputOutput.inputDatasetEdges` | P0 | ✅ | `:1133-1161`. Gated by `materializeDataset` / `captureColumnLevelLineage` config flags. |
| `RunEvent.outputs[]` | `dataJobInputOutput.outputDatasetEdges` | P0 | ✅ | `:1163-1191` |
| Required-field validation | 400 on missing `schemaURL` / `producer` / `eventTime` | P0 | ❌ | No pre-dispatch validation. Missing fields cause downstream NPEs that surface as 500. Missing `schemaURL` on a request with all other fields is silently accepted and the event is ingested. |
| Error response shape | Structured JSON `{code, message, details}` | P0 | ❌ | `LineageApiImpl.java:63-66` returns empty 500. `:99` re-throws as `RuntimeException`. |
| Request atomicity | All MCPs from one event commit together | P0 | ❌ | The controller loops over MCPs and calls `_entityService.ingestProposal` per MCP. A mid-stream validation failure (e.g. `OTHER` eventType) leaves earlier MCPs (`dataFlowInfo`, `status`, `dataJobInfo`, `dataJobInputOutput`) committed before the run-event MCP fails. |
| Auth null-safety | 401 on missing actor | P0 | ❌ | `:70` calls `AuthenticationContext.getAuthentication()` without null check. |

### A.4.2 Run facets

| Facet | Target aspect | Prio | Status | Notes |
|---|---|---|---|---|
| `NominalTimeRunFacet` | `dataProcessInstanceProperties.created` + `nominalEndTime` custom property | P0 | ❌ | Facet never read. |
| `ParentRunFacet` | `dataProcessInstanceRelationships.parentInstance` | P0 | 🟡 | Read at `:1107-1131`. Resolved to a parent `DataJob` URN and written to `dataJobInputOutput.inputDatajobEdges`, not to the DPI relationship aspect. Run-to-run link is lost. |
| `ErrorMessageRunFacet` | FAILURE run event + custom properties | P0 | ❌ | Facet never read. FAIL/ABORT events lose the message, language, and stack trace. |
| `ProcessingEngineRunFacet` | Orchestrator input + `versionInfo.version` on DataFlow | P0 | 🟡 | `name` is used for orchestrator derivation at `:317`. `name`/`version`/`openlineageAdapterVersion` copied into DPI/Flow `customProperties` at `:580-601`. Not written to `versionInfo`. |
| `ExternalQueryRunFacet` | `operation.customProperties.externalQueryId` on outputs | P1 | ❌ | Not read. |
| `EnvironmentVariablesRunFacet` | `dataProcessInstanceProperties.customProperties` | P2 | ❌ | Not read. |
| `TagsRunFacet` | `globalTags` on parent DataJob | P2 | ❌ | The only tag path (`generateTags`, `:540-578`) reads from the Airflow custom run facet `run.facets.airflow.dag.tags`. Standard `TagsRunFacet` is never consulted. |
| `JobDependenciesRunFacet` | `dataJobInputOutput.inputDatajobs` | P2 | ❌ | Not read. |
| `ExtractionErrorRunFacet` | FAILURE run event + custom property | P2 | ❌ | Not read. |

### A.4.3 Job facets

| Facet | Target aspect | Prio | Status | Notes |
|---|---|---|---|---|
| `DocumentationJobFacet` | `dataJobInfo.description` | P0 | 🟡 | Read at `:405-411`. Written to `dataJobInfo.description` (`:817`, correct target) **and** to `dataFlowInfo.description` (`:346`, surplus). The DataJob write is correct; the DataFlow write is spurious and will move behind the `documentationTarget` config flag. |
| `SourceCodeLocationJobFacet` | `dataJobInfo.externalUrl` | P0 | ❌ | Not read. No `getSourceCodeLocation()` call exists in the converter. |
| `SourceCodeJobFacet` | `dataTransformLogic.transformations[].rawTransformation` | P1 | ❌ | Not read. |
| `SQLJobFacet` | `dataTransformLogic.transformations[].queryStatement` + mirror to outputs | P0 | 🟡 | Read at `:506-525` and `:935-958`. The query text is used only to extract a target table name from `MERGE INTO` statements. The SQL itself is never persisted as an aspect. |
| `OwnershipJobFacet` | `ownership` on DataJob | P0 | ❌ | Read at `:373-403`. An `Ownership` object is built (owner type hardcoded to `DEVELOPER`, source hardcoded to `SERVICE`) and assigned to `jobBuilder.flowOwnership(...)`. The downstream `DatahubJob.toMcps()` serializer does not emit an `ownership` MCP from this field. Direct aspect-store query confirms neither the DataJob nor the DataFlow receives an `ownership` aspect. Total drop. Surfaces as #14458. |
| `TagsJobFacet` | `globalTags` on DataJob | P0 | ❌ | Not read. The only tag path reads the Airflow custom run facet. Surfaces as #14458. |
| `JobTypeJobFacet` | `subTypes` + `dataJobInfo.type` + DataPlatform override | P0 | 🟡 | Read at `:1038-1041` only to special-case `RDD_JOB` (skip RDD-stage events). `processingType`, `integration`, and `jobType` are not persisted. |

### A.4.4 Dataset facets

| Facet | Target aspect | Prio | Status | Notes |
|---|---|---|---|---|
| `SchemaDatasetFacet` | `schemaMetadata.fields` (recursive nested) | P0 | 🟡 | `:1323-1356`. Field lists and recursive nested structs are written. Two secondary bugs: (1) the type-name mapping at `:1303` is case-sensitive, so lowercase OL types (`"string"`, `"int"`) map to `StringType`/`NumberType` but uppercase (`"STRING"`, `"INT"`, common from Trino/JDBC producers) map to `NullType`; (2) `platformSchema` is hardcoded to `MySqlDDL` with the raw OL field list encoded into `tableSchema`, regardless of the actual dataset platform. |
| `DatasourceDatasetFacet` | `dataPlatformInstance.instance` + `datasetProperties.externalUrl` | P0 | 🟡 | Used for dataset-URN platform/instance derivation in `convertOpenlineageDatasetToDatasetUrn`. The `uri` is not written to `externalUrl`. No dataset-level `dataPlatformInstance` aspect is emitted; the aspect present on each dataset URN is auto-derived from the URN itself. |
| `ColumnLineageDatasetFacet` | `upstreamLineage.fineGrainedLineages[]` on the output Dataset | P0 | 🟡 | Read at `:413-538`. Emitted as a JSON-patch MCP on `dataJob.dataJobInputOutput.fineGrainedLineages[]` — i.e. on the DataJob, not on the output Dataset. Aspect-store query for an output Dataset on the column-lineage test confirms no `upstreamLineage` aspect; query for the corresponding DataJob confirms the `fineGrainedLineages` patch content. Secondary divergences: `transformations[].description` and the `masking` flag are discarded; `confidenceScore` is hardcoded to `0.5`; the 1.0 form of the facet (without `transformations[]`) degrades to a literal `transformOperation = "TRANSFORM"`. |
| `OwnershipDatasetFacet` | `ownership` on Dataset | P1 | ❌ | Not read. |
| `LifecycleStateChangeDatasetFacet` | `status.removed` for DROP/TRUNCATE | P1 | ❌ | Not read. |
| `SymlinksDatasetFacet` | `siblings.siblings[]` | P1 | 🟡 | Read at `:132-138` and `:980-982`. Used to rewrite the dataset URN (replacing the OL identifier with the symlinked one) and to find merge-target tables. No `siblings` aspect is ever emitted. |
| `StorageDatasetFacet` | `datasetProperties.customProperties` | P2 | ❌ | Not read. |
| `DatasetVersionDatasetFacet` | `versionProperties.version.versionTag` | P1 | ❌ | Not read. |
| `DocumentationDatasetFacet` | `datasetProperties.description` | P0 | ❌ | Not read. |
| `DatasetTypeDatasetFacet` | `subTypes.typeNames` | P1 | ❌ | Not read. |
| `CatalogDatasetFacet` | `dataPlatformInstance.instance` | P1 | ❌ | Not read. |
| `HierarchyDatasetFacet` | `container` aspect | P2 | ❌ | Not read. |
| `TagsDatasetFacet` | `globalTags` on Dataset | P1 | ❌ | Not read. |

### A.4.5 Input dataset facets

| Facet | Target aspect | Prio | Status | Notes |
|---|---|---|---|---|
| `DataQualityMetricsInputDatasetFacet` | `datasetProfile` time-series MCP | P1 | ❌ | Not read. |
| `InputStatisticsInputDatasetFacet` | `operation` on input, `READ` | P1 | ❌ | Not read. |

### A.4.6 Output dataset facets

| Facet | Target aspect | Prio | Status | Notes |
|---|---|---|---|---|
| `OutputStatisticsOutputDatasetFacet` | `operation` on output (`numAffectedRows`, `numAffectedBytes`) | P0 | ❌ | Not read. |
| `DataQualityAssertionsDatasetFacet` | `assertion` entity + `assertionRunEvent` | P2 | ❌ | Not read. |

### A.4.7 Custom (non-standard) facet handlers

The converter handles a set of producer-specific custom facets via
`RunFacet.getAdditionalProperties()`. These are not standard OpenLineage
facets and are listed for completeness; the RFC does not modify them.

| Custom facet key | Handler | Source location |
|---|---|---|
| `spark_jobDetails` | `processSparkJobDetails` | `:646-660` |
| `processing_engine` (additionalProperties path) | `processProcessingEngine` | `:647` area |
| `spark_version` | `processSparkVersion` | `:678` |
| `spark_properties` | `processSparkProperties` | `:690` |
| `airflow` | `processAirflowProperties` | `:703` |
| `spark.logicalPlan` | `processSparkLogicalPlan` | `:715` |
| `unknownSourceAttribute` | `processUnknownSourceAttributes` | `:723` |

`processAirflowProperties` reads `run.facets.airflow.dag.tags` and emits
`GlobalTags` — functionally overlapping with the standard `TagsJobFacet` /
`TagsRunFacet`. Resolving the overlap is an unresolved question in the main
RFC.

### A.4.8 Baseline aspect set per RunEvent

Against the current implementation, every successful `RunEvent` request
produces the same 10-aspect baseline regardless of which facets it carries:

```
 dataFlow:            dataFlowInfo, status
 dataJob:             dataJobInfo, dataJobInputOutput, status
 dataProcessInstance: dataProcessInstanceInput, dataProcessInstanceOutput,
                      dataProcessInstanceProperties, dataProcessInstanceRunEvent,
                      dataProcessInstanceRelationships
```

Datasets referenced via `inputs[]`/`outputs[]` receive only `datasetKey` +
`status`. A `schemaMetadata` aspect is written for each dataset that carries
a `SchemaDatasetFacet`. A `dataJobInputOutput` PATCH MCP carries
`fineGrainedLineages` entries for each dataset that carries a
`ColumnLineageDatasetFacet`. No `upstreamLineage` aspect is ever written on
the dataset side, regardless of whether column lineage is present.

---

## A.5 OpenAPI contract drift

`metadata-service/openapi-servlet/src/main/resources/openlineage/openlineage.json`:

| Element | Spec expectation | Current state | Status |
|---|---|---|---|
| Declared spec version | matches embedded component schemas | `info.version: "2-0-2"` (line 5) but `components.schemas` still use the older `BaseFacet` shape (`_producer`/`_schemaURL`, no `JobEvent`/`DatasetEvent` definitions) | 🟡 |
| `requestBody.content.application/json.schema` | `oneOf [RunEvent, JobEvent, DatasetEvent]` | `{ "type": "string" }` (lines 22-28) | ❌ |
| Documented responses | At least `200`, `400`, `500` | Only `200` documented (lines 30-34) | ❌ |
| Operation set | `POST /lineage` | `POST /lineage` only | ✅ |

---

## A.6 Milestone roll-up

### Milestone A — P0 baseline

| Section | Total P0 | ✅ | 🟡 (rework) | ❌ (new) |
|---|---|---|---|---|
| Envelope / dispatch / contract / errors / atomicity | 16 | 5 | 3 | 8 |
| Run facets | 4 | 0 | 2 | 2 |
| Job facets | 6 | 0 | 3 | 3 |
| Dataset facets | 4 | 0 | 3 | 1 |
| OutputDataset facets | 1 | 0 | 0 | 1 |
| **Total** | **31** | **5** | **11** | **15** |

A third of the P0 items already have partial converter code that writes to
an adjacent but incorrect target; this reduces to rerouting work. The
remainder is new implementation (event-type dispatch, required-field
validation, structured error model, request atomicity, registered-platform
validation, `NominalTimeRunFacet`, `ErrorMessageRunFacet`,
`SourceCodeLocationJobFacet`, `TagsJobFacet`, `OwnershipJobFacet` MCP
persistence, `DocumentationDatasetFacet`,
`OutputStatisticsOutputDatasetFacet`).

### Milestone B — P1

14 items. None of the P1 facets are currently read by the converter.

### Milestone C — P2

8 items covering assertions, environment variables, hierarchy, run-level
tags, extraction-error reporting, data-quality assertion entities.

---

## A.7 Linked issues and PRs

All open issues on `datahub-project/datahub` matching
`state:open openlineage in:title,body` at the time of writing, filtered for
relevance to the REST endpoint.

### A.7.1 In scope — closed or substantially addressed by this RFC

| # | Title | Relevant appendix section |
|---|---|---|
| [#16961](https://github.com/datahub-project/datahub/issues/16961) | OpenLineage with custom producer not working | A.4.1 (free-form producer) |
| [#15196](https://github.com/datahub-project/datahub/issues/15196) | OpenLineage JobEvents are not processed | A.4.1 (JobEvent dispatch) |
| [#14458](https://github.com/datahub-project/datahub/issues/14458) | TagsJobFacet and OwnershipJobFacet are ignored on OpenLineage REST-Calls | A.4.3 (`OwnershipJobFacet`, `TagsJobFacet`) |
| [#13011](https://github.com/datahub-project/datahub/issues/13011) | Error when Integrating openlineage api with Trino's OpenLineage event listener | A.4.1 (free-form producer) — same root cause as #16961 |

### A.7.2 Adjacent — shares code paths with the REST endpoint

| # | Title | Relationship |
|---|---|---|
| [#13929](https://github.com/datahub-project/datahub/issues/13929) | Data lineage is not sent to datahub gms | Spark agent path (`acryl-spark-lineage`) calling into `OpenLineageToDataHub`. The orchestrator-resolution and facet-rerouting work in Milestone A runs through the same converter, so the reported `Query execution is null` symptom may resolve as a side effect; the RFC does not commit to it. |
| [#16018](https://github.com/datahub-project/datahub/issues/16018) | Feature request: disable lineage ingestion per source (Tableau) to avoid overwriting external lineage | The same cross-producer overwrite concern that the RFC addresses for `DatasetEvent` via `datasetEventNamespaceByProducer`. Directly out of scope for this RFC; the recommendation informs the design. |

### A.7.3 Open PRs touching the OpenLineage area

| # | Title | Relationship |
|---|---|---|
| [#16890](https://github.com/datahub-project/datahub/pull/16890) | feat(ingest/spark): upgrade OpenLineage from 1.38.0 to 1.45.0 with full shadow JAR shading | Client library version bump for the Spark agent. Does not regenerate `openlineage.json` or change the converter. |
| [#14911](https://github.com/datahub-project/datahub/pull/14911) | feat(ingest/spark): Initial commit for openlineage 1_38 upgrade | Earlier client version bump. Stale. |
| [#13066](https://github.com/datahub-project/datahub/pull/13066) | feat: accept trino as orchestrator | Adds Trino to the hard-coded orchestrator allow-list. Partial fix for #13011; the RFC's free-form producer resolution supersedes this approach. |
| [#14573](https://github.com/datahub-project/datahub/pull/14573) | fix(ingest/spark): Map sqlserver to mssql in dialect detection | Spark agent only. |

None of the open PRs address the dispatch, contract, atomicity, or
facet-coverage gaps cataloged in this appendix.
