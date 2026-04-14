- Start Date: 2026-04-14
- RFC PR: (after opening the RFC PR, update this with a link to it and update the file name)
- Discussion Issue:
- Implementation PR(s):

# OpenLineage REST endpoint — spec compliance

## Summary

Bring the `POST /openapi/openlineage/api/v1/lineage` endpoint into alignment with
the OpenLineage 2-0-2 specification. Accept all three root event types
(`RunEvent`, `JobEvent`, `DatasetEvent`), accept any spec-conforming `producer`
URI, route the standard facets to their target DataHub aspects, return
structured errors for spec-invalid events, and ship an OpenAPI contract that
matches the events the endpoint accepts.

## Basic example

A `JobEvent` (no `run` block, no `eventType`) is a valid OpenLineage event. The
target behavior is:

```bash
curl -X POST http://localhost:8080/openapi/openlineage/api/v1/lineage \
  -H 'Content-Type: application/json' \
  -d '{
    "eventTime": "2026-04-14T10:00:00Z",
    "producer":  "https://example.com/my-pipeline-tool",
    "schemaURL": "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/JobEvent",
    "job":     { "namespace": "crm", "name": "load_dp_customer" },
    "inputs":  [ { "namespace": "crm_unload",   "name": "customer" } ],
    "outputs": [ { "namespace": "dataproducts", "name": "dp_customer" } ]
  }'
# HTTP 200
# Writes: DataFlow + DataJob + dataJobInputOutput + Dataset(key,status) ×2.
# No DataProcessInstance MCPs (JobEvent is not a run state transition).
```

A `RunEvent` from a custom producer URI is also accepted. The orchestrator name
is derived from typed facets first (`ProcessingEngineRunFacet.name`,
`JobTypeJobFacet.integration`), then a configured default, then the producer
URI as a fallback; the derivation function is total and never throws.

A spec-invalid event returns a structured 400:

```json
{ "code": "INVALID_EVENT",
  "message": "schemaURL is required",
  "details": { "field": "schemaURL" } }
```

## Motivation

DataHub advertises an OpenLineage-compatible REST endpoint. The endpoint
accepts a narrow slice of the spec and silently drops several standard facets;
known user-visible failures include:

- HTTP 500 (`Unable to determine orchestrator`) when the producer URI is not on
  a hard-coded allow-list
  ([#16961](https://github.com/datahub-project/datahub/issues/16961),
  [#13011](https://github.com/datahub-project/datahub/issues/13011)).
- HTTP 500 (`NullPointerException`) when the event is a `JobEvent`
  ([#15196](https://github.com/datahub-project/datahub/issues/15196)).
- `TagsJobFacet` and `OwnershipJobFacet` are not persisted on the REST path
  ([#14458](https://github.com/datahub-project/datahub/issues/14458)).
- The shipped OpenAPI contract declares the request body as `{"type":
  "string"}`, so generated clients send JSON-encoded strings instead of
  OpenLineage events.

Beyond the tracked issues, the canonical OpenLineage Python/Java reference
client produces `DataFlow` URNs pointing at `urn:li:dataPlatform:client` — a
ghost platform entity that does not exist in DataHub's model — because the
orchestrator-derivation regex captures the last path segment of the producer
URL. Different canonical-OL producer URLs yield different ghost platforms,
fragmenting related lineage.

Making "spec-compliant OpenLineage producer" a sufficient condition for
interoperating with DataHub requires removing the per-producer special-casing
in the converter and routing each standard facet to a documented target
aspect.

## Requirements

1. Every spec-valid OpenLineage 2-0-2 event is accepted with HTTP 2xx and
   produces at least one MCP. Failures propagate through the existing
   openapi-servlet exception advice — the controller's current
   `catch (Exception e) → 500` block is removed so typed Jackson errors and
   mapper-layer runtime failures both reach `GlobalControllerExceptionHandler`
   with a structured error body.
2. All three root event types — `RunEvent`, `JobEvent`, `DatasetEvent` — are
   dispatched and ingested on paths appropriate to the event's semantics.
3. The `producer` field is treated as a free-form URI per spec. The
   orchestrator/platform name is derived from typed facets first; the
   derivation function is total.
4. Standard facets enumerated in the appendix are routed to their target
   DataHub aspects on the entity the spec attaches them to (Job facets →
   `DataJob`, Run facets → `DataProcessInstance`, Dataset facets → `Dataset`).
5. The `openlineage.json` OpenAPI contract that the servlet ships matches the
   events the server accepts.
6. The implementation is testable against the OpenLineage spec without
   DataHub-specific assumptions. A parameterized test harness loads JSON
   fixtures from the OpenLineage / Marquez ecosystem and asserts both the HTTP
   response and the resulting MCP set.
7. Behavior changes are observable. Unmapped facets log at debug level so new
   producer additions are visible without producing 500s.
8. Ingestion of a single event is atomic at the request boundary. A mid-stream
   failure does not leave partial entity writes in the aspect store.

### Extensibility

- Adding a facet mapping is a matter of writing a method in the converter and
  registering it in the per-event-type dispatcher; the controller does not
  need to change.
- Per-producer customization (orchestrator override, platform-instance
  override, dataset-URN namespace prefix) is supported through
  `DatahubOpenlineageConfig` so site operators can adapt the endpoint without
  code changes.
- New OpenLineage spec versions are absorbed by regenerating `openlineage.json`
  and bumping the embedded `io.openlineage:openlineage-java` client. The
  dispatcher and facet mappings are version-stable as long as the spec stays
  additive, which matches OpenLineage's declared versioning policy
  (`spec/Versioning.md`: "schema changes should only add optional fields").

## Non-Requirements

- Changes to the Spark or Airflow agents (`acryl-spark-lineage`,
  `metadata-ingestion-modules/airflow-plugin`) are out of scope; their event
  shapes already match what the REST endpoint will accept.
- Persisting raw OpenLineage event payloads is out of scope. Marquez stores
  the full JSON in `lineage_events` for later replay; DataHub has no analogous
  store and adding one is outside this RFC.
- Request-layer validation of payloads is out of scope. Typed Jackson
  deserialization against the `io.openlineage:openlineage-java` beans
  catches whatever the beans' own typed fields catch (wrong JSON shapes,
  unknown enum values, malformed timestamps) and nothing beyond that.
- Custom (non-standard) facets sent via `additionalProperties` keep their
  producer-specific handlers (Spark, Airflow). Unifying them with the standard
  facet table is a follow-up.
- This RFC does not propose UI changes.

## Detailed design

The design is organized around three concerns: dispatch at the controller,
entity-and-URN shape in the converter, and facet-to-aspect routing. The
companion [appendix](./000-openlineage-spec-compliance-appendix.md) carries
the detailed reference material:

- **Appendix §A.2 — Test suite overview.** Layout and correlation semantics
  of the Hurl end-to-end suite, runner pipeline, and per-request MCP
  attribution.
- **Appendix §A.3 — OpenLineage ↔ DataHub ↔ Marquez mapping.** Per-element
  cross-walk covering the envelope, every standard facet, and how each
  receiver stores the same OL concept.
- **Appendix §A.4 — Status quo and gaps.** Per-facet implementation status
  against the converter source, backed by aspect-store verification.

### Endpoint dispatch

`LineageApiImpl.postRunEventRaw(String body)` currently calls
`OpenLineageClientUtils.runEventFromJson(body)` unconditionally. The new
shape:

1. Deserialize the body into `LineageBody` — the existing Jackson
   discriminated-union interface — via the openapi-servlet `ObjectMapper`.
   `LineageBody` selects one of `OpenLineage.RunEvent`,
   `OpenLineage.JobEvent`, `OpenLineage.DatasetEvent` based on payload shape
   (`run` present → `RunEvent`; `dataset` present → `DatasetEvent`; else →
   `JobEvent`). Today the interface pins `schemaURL` to a stale `2-0-0`
   path and discriminates by exact-string match; this RFC replaces that
   strategy with a shape-based custom `TypeIdResolver`, since real
   producers send arbitrary `schemaURL` values. The `ObjectMapper` used
   here installs a permissive `ZonedDateTime` deserializer that falls back
   to `LocalDateTime.parse(s).atZone(UTC)` on `DateTimeParseException`, so
   naive timestamps from the OpenLineage reference Python client
   (`"2021-11-03T10:53:52.427343"`, emitted without an offset) are treated
   as UTC and accepted. Matches Marquez's behavior on the same payloads.
2. Dispatch to one of three mapper entry points on `RunEventMapper`:
   - `mapRunEvent(RunEvent, MappingConfig)` — emits `DataFlow`, `DataJob`,
     `DataProcessInstance`, and referenced `Dataset` aspects.
   - `mapJobEvent(JobEvent, MappingConfig)` — emits `DataFlow`, `DataJob`,
     `dataJobInputOutput`, and referenced `Dataset` aspects. No DPI aspects.
   - `mapDatasetEvent(DatasetEvent, MappingConfig)` — emits `Dataset` aspects
     only.
3. All MCPs produced by a single event are ingested through a batched entity
   service call (`EntityServiceImpl.ingestProposals(List<MCP>, ...)`) so the
   request succeeds or fails as a unit; no partial writes.
4. `AuthenticationContext.getAuthentication()` is null-checked and returns
   401 when the actor is missing. The controller's current
   `catch (Exception e) → 500` block is removed; Jackson's typed exceptions
   (`MismatchedInputException` on wrong JSON shapes, unknown enum values,
   malformed `ZonedDateTime`, unparseable JSON) and mapper-layer runtime
   failures propagate to the existing `GlobalControllerExceptionHandler`,
   which produces a structured error body.

### Conceptual entity mapping

| OpenLineage concept | DataHub entity | URN shape |
|---|---|---|
| `Job` (`namespace`, `name`) | `DataJob` | `urn:li:dataJob:(<DataFlow URN>, <task id>)` |
| Containing flow (orchestrator + namespace) | `DataFlow` | `urn:li:dataFlow:(<orchestrator>, <flow id>, <namespace/instance>)` |
| `Run` (`runId`) | `DataProcessInstance` | `urn:li:dataProcessInstance:<runId>` |
| `Dataset` (`namespace`, `name`) | `Dataset` | `urn:li:dataset:(urn:li:dataPlatform:<derived>, <name>, PROD)` |
| Run state transition (`eventType`) | `dataProcessInstanceRunEvent` time-series MCP | — |
| `inputs[]` / `outputs[]` | `dataJobInputOutput` on DataJob + `upstreamLineage` on each output Dataset | — |

Shape decisions:

- **Job → DataJob / DataFlow split.** The existing convention is preserved:
  split `Job.name` on the first `.` (prefix = flow id, suffix = task id). If
  no `.` is present, `flowId == jobName` and the flow contains a single task
  that shares the flow's id. Per-producer override is configurable.
- **Orchestrator name.** Resolution order:
  `ProcessingEngineRunFacet.name` (lower-cased) →
  `JobTypeJobFacet.integration` (lower-cased) →
  `DatahubOpenlineageConfig.orchestrator` →
  a best-effort parse of the producer URI →
  the configured default (`openlineage`). The function is total.
- **DataPlatform URN for the flow.** Derived from the orchestrator name above.
  A validation step verifies the resulting `urn:li:dataPlatform:<name>`
  resolves to a registered platform entity; if it does not, the configured
  default is used instead. This prevents ghost platform references of the
  kind surfaced by the current endpoint.
- **DataProcessInstance URN.** Uses `Run.runId` directly.
- **Dataset URN.** Reuses `convertOpenlineageDatasetToDatasetUrn`. The
  `DatasourceDatasetFacet.uri`, when present, is written to
  `datasetProperties.externalUrl`.
- **`eventType` handling.** Per spec, `eventType` is optional on `RunEvent`.
  A missing `eventType` is treated as `OTHER` (supplementary-metadata event)
  and produces no `dataProcessInstanceRunEvent` MCP. Each enum value maps to
  exactly one status / result-type pair; the `OTHER` branch emits no run-event
  MCP at all rather than writing the Pegasus sentinel value that currently
  fails aspect validation.

### Facet routing

The full facet-to-aspect table is in [appendix §A.4](./000-openlineage-spec-compliance-appendix.md#a4-status-quo-and-gaps)
and the OpenLineage ↔ DataHub ↔ Marquez cross-walk is in
[appendix §A.3](./000-openlineage-spec-compliance-appendix.md#a3-openlineage--datahub--marquez-mapping).
Summary by milestone:

**Milestone A — P0 baseline.** 31 items total: 16 envelope items
(event-type dispatch, free-form producer, required-field validation,
structured error body, request atomicity, registered-platform validation,
URN split, eventType enum handling, authentication null-safety, and the
existing baseline aspects that already work) plus 15 P0 facets required for
everyday interoperability: `NominalTimeRunFacet`, `ParentRunFacet`,
`ErrorMessageRunFacet`, `ProcessingEngineRunFacet`, `DocumentationJobFacet`,
`SourceCodeLocationJobFacet`, `SQLJobFacet`, `OwnershipJobFacet`,
`TagsJobFacet`, `JobTypeJobFacet`, `SchemaDatasetFacet`,
`DatasourceDatasetFacet`, `ColumnLineageDatasetFacet`,
`DocumentationDatasetFacet`, `OutputStatisticsOutputDatasetFacet`. Closes
#16961, #15196, #13011, #14458.

**Milestone B — P1 standard producer coverage.** 14 items covering
`ExternalQueryRunFacet`, `SourceCodeJobFacet`, `OwnershipDatasetFacet`,
`LifecycleStateChangeDatasetFacet`, `SymlinksDatasetFacet`,
`DatasetVersionDatasetFacet`, `DatasetTypeDatasetFacet`,
`CatalogDatasetFacet`, `TagsDatasetFacet`,
`DataQualityMetricsInputDatasetFacet`, `InputStatisticsInputDatasetFacet`,
plus `JobEvent`/`DatasetEvent` polish (multi-event idempotency, cross-producer
dataset scoping).

**Milestone C — P2 quality and edge cases.** Assertions, environment
variables, hierarchy, run-level tags, extraction-error reporting.

### Configuration surface

`DatahubOpenlineageConfig` gains the following options. Each default preserves
current behavior where feasible so operators see no change without an opt-in.

- `orchestratorDefault` (string, default `openlineage`) — value used when no
  facet- or producer-derived orchestrator is found.
- `documentationTarget` (enum: `dataJob`, `dataFlow`, `both`, default `both`
  during the deprecation window, then `dataJob`) — controls where
  `DocumentationJobFacet` is written.
- `ownershipTarget` (enum: same shape as above, same default trajectory) —
  controls where `OwnershipJobFacet` is written.
- `datasetEventNamespaceByProducer` (boolean, default `false`) — when true,
  dataset URNs ingested via `DatasetEvent` carry a producer-scoped platform
  instance, preventing cross-producer overwrite.
- `requireRegisteredPlatform` (boolean, default `true`) — when true, an
  orchestrator name that does not resolve to a registered `dataPlatform` entity
  is rejected in favor of the configured default, preventing ghost-platform
  URNs.

### Error responses

The endpoint returns a structured JSON body matching the shape used elsewhere
in the openapi-servlet:

```json
{ "code": "INVALID_EVENT",
  "message": "schemaURL is required",
  "details": { "field": "schemaURL" } }
```

HTTP status mapping:

- `400` — deserialization failure, missing required envelope field, or
  type-invalid payload.
- `401` — missing or invalid authentication.
- `500` — unexpected runtime failure. The `details` object contains the
  exception class and message.

All MCPs produced from a single event are ingested in one batch. Either every
MCP is committed or none is.

### OpenAPI contract

`metadata-service/openapi-servlet/src/main/resources/openlineage/openlineage.json`
is regenerated from upstream OpenLineage 2-0-2. The request body schema
references a `oneOf` over `RunEvent`, `JobEvent`, and `DatasetEvent`. Error
response schemas are documented for `400`, `401`, `500`. Generated clients
stop sending JSON-encoded strings.

### Test strategy

The implementation is gated by three layers of tests, separated by concern:

1. **Payload / HTTP contract — Hurl suite** under
   `smoke-test/tests/openapi/openlineage/hurl/`. ~109 requests across 10
   files, one file per spec area. Every request carries a unique
   `User-Agent` header so the GMS log stream can be sliced per request; see
   [appendix §A.2](./000-openlineage-spec-compliance-appendix.md#a2-test-suite-overview)
   for layout and correlation semantics. The suite encodes the full
   spec-compliance contract as TDD; the subset reachable under this RFC's
   scope is the positives plus whatever Jackson's typed deserialization
   catches on its own (type mismatches, unknown `eventType`, malformed
   `ZonedDateTime`, unparseable JSON). The remaining negatives — missing
   required fields, dispatch exclusion, naive-tz positives, `format: uri` —
   are aspirational against this RFC and gate follow-up validation work.
   A pytest wrapper at
   `smoke-test/tests/openapi/openlineage/test_openlineage_spec.py` parametrizes
   the suite for invocation from the standard smoke-test runner; the
   hurl-native `run.sh` wrapper runs the same fixtures with additional GMS-log
   correlation for attribution-level MCP auditing (non-blocking, operator
   tool).
2. **MCP mapping — Java parameterized test** in
   `metadata-service/openapi-servlet/src/test/java/io/datahubproject/openapi/openlineage/`
   loading JSON fixtures from two upstream corpora (both Apache 2.0,
   attribution in `NOTICE`): Marquez's `api/src/test/resources/open_lineage/`
   for envelope and facet shapes, and
   `github.com/OpenLineage/compatibility-tests` `consumer/scenarios/*/events/*.json`
   for cross-consumer canonical scenarios (`simple_run_event`, `CLL`,
   `airflow`, `spark_dataproc_*`). Each fixture is called through
   `LineageApiImpl.postRunEventRaw` against a mocked `EntityServiceImpl`;
   assertions are on the captured MCP set. Covers the facet-to-aspect
   routing that the Hurl suite deliberately leaves unverified.
3. **Aspect-store verification** as a pre-merge integration step, querying
   `GET /openapi/v3/entity/<type>/<urn>` against a running instance to confirm
   that per-fixture expected aspects are persisted end-to-end.

Fixture coverage spans: every spec-required event shape, producer URI
variation, field-type case variation (lowercase and uppercase),
Unicode/nanosecond/non-UTC edge cases, state-machine sequences, and unknown
facet tolerance. A separate corpus of real-world producer payloads
(`hurl/legacy/`) guards against regressions on pre-existing user
configurations.

## How we teach this

The DataHub OpenLineage endpoint is an existing feature; this RFC sharpens its
contract rather than introducing new terminology. Documentation changes:

- `docs/lineage/openlineage.md` gains a "Spec compliance" section listing
  supported event types, the orchestrator-resolution order, and the
  configuration knobs above.
- The producer-compatibility subsection links to OpenLineage's producer
  registry rather than maintaining a DataHub-side allow-list.
- `docs/how/updating-datahub.md` documents the documentation-target and
  ownership-target config changes, the parallel-write window, and the
  migration procedure for sites that depend on the current DataFlow-side
  writes.
- The regenerated OpenAPI contract is the source of truth for clients;
  consumers generating from the spec observe the new request-body shape
  automatically.

The audience is primarily backend developers and operators integrating
third-party OpenLineage producers. Frontend changes are not required.

## Drawbacks

- **Behavioral change for existing users.** Sites that depend on
  `DocumentationJobFacet` or `OwnershipJobFacet` landing on `DataFlow` see the
  aspects move to `DataJob` after the parallel-write window closes. The
  `documentationTarget` and `ownershipTarget` config knobs allow an extended
  transition.
- **Larger facet surface to maintain.** Three event types plus 31 P0 items is
  more surface than today's converter. Mitigated by the test fixture strategy:
  every facet has a fixture and every fixture asserts a specific MCP shape.
- **Loss of an implicit safety net.** The current allow-list rejects events
  from unknown producers, which accidentally prevents some misconfigured
  pipelines from writing to DataHub. After this RFC, any producer is accepted.
  Operators relying on the rejection as a safety net enforce it at the
  auth/network layer instead.
- **Divergence from Marquez's storage model.** Marquez persists raw event JSON
  for later replay; DataHub does not. Facets that DataHub does not map are
  dropped. The unmapped-facet debug log makes the gap observable.

## Alternatives

- **Request-layer schema validation.** Pre-validating requests against the
  OpenLineage JSON Schema — via `networknt/json-schema-validator`, an
  OpenAPI request validator like `swagger-request-validator-spring-webmvc`,
  or a hand-rolled null-check / `@ExceptionHandler` layer — would catch
  missing required fields, `format: uri` / `format: date-time` violations,
  and enum-domain violations uniformly. Rejected for this RFC. The scope is
  the bug fixes, dispatch, facet routing, and mapping; adding a validation
  layer alongside them is a separate concern with its own tradeoffs
  (dependency footprint vs. reuse, schema vs. OpenAPI vs. Java checks,
  cross-version compatibility). Typed Jackson catches what it catches; the
  rest is whatever the OL beans expose.
- **Replace the converter with a pass-through to a new `rawLineageEvent`
  entity.** Storing the raw JSON event the way Marquez does gives
  forward-compatibility with any facet shape but requires a new entity type,
  time-series indexing, and a UI to browse it. Out of scope. Rejected.
- **DataHub-side producer registry.** Writing one Java class per supported
  producer (Airflow, Trino, dbt, Spark, …) with its own field-extraction
  logic is the direction the converter is currently evolving. It does not
  scale and conflicts with the spec's producer-agnostic intent. Rejected.
- **Vendor-fork the OpenLineage Java client.** Tempting for fields like
  `nominalEndTime` that DataHub wants typed access to. Reading through
  `additionalProperties` is the lower-maintenance path. Rejected.

**Prior art.** Marquez is the de-facto receiver implementation for OpenLineage
in the wider ecosystem. It ingests events by persisting raw JSONB facet blobs
in `run_facets` / `job_facets` / `dataset_facets` and selectively promotes a
few well-known fields into typed columns (`jobs.description`, `jobs.location`,
`runs.parent_run_uuid`, `dataset_fields`, `column_lineage`). This RFC follows
the same shape on the DataHub side: typed mapping for standard facets,
graceful tolerance for everything else, observable debug logging for the
unmapped ones. The Marquez JSON test fixtures are reused as DataHub's spec
corpus (appendix A.3 cross-walks each fixture to the DataHub aspect it
exercises).

## Rollout / Adoption Strategy

- **Default on.** The behavior changes (event-type dispatch, free-form
  producer, facet rerouting, atomic ingestion, structured error responses)
  ship enabled by default.
- **Parallel-write window for rerouted facets.** For one minor release,
  `documentationTarget` and `ownershipTarget` default to `both`. Both the new
  (DataJob) and legacy (DataFlow) aspect locations are written. The next
  minor release flips the default to `dataJob`.
- **Migration documentation.** A section in `docs/how/updating-datahub.md`
  lists affected aspects, the config knobs, and the rollback procedure. The
  note cross-links the tracked issues so operators searching for a known
  symptom land on the migration page.
- **Backfill.** Not required. Existing `DataFlow.dataFlowInfo.description` and
  `DataFlow.ownership` records remain valid. New events populate the DataJob
  location; the DataFlow location continues to receive writes during the
  parallel-write window.

## Future Work

- **DataQualityAssertionsDatasetFacet → assertion entity.** Wires OpenLineage
  data-quality results into DataHub's `assertion` entity so OL-emitted quality
  checks appear alongside Great Expectations and dbt tests.
- **OpenLineage-driven DataProduct entity.** `JobEvent` ingestion provides
  enough information to materialize the OL "data product" concept once that
  part of the spec stabilizes.
- **Streaming ingest path.** Every event currently hits
  `EntityServiceImpl.ingestProposal` synchronously. Routing through Kafka
  (the path used by the MCE consumer) smooths bursty producers and decouples
  the REST endpoint from GMS write latency.
- **Marquez-as-oracle integration test.** Run each Marquez fixture through
  both Marquez and DataHub and compare the semantic output (entity count,
  lineage edges, schema fields). Gives a black-box conformance gate anchored
  to the reference implementation.
- **Contribute a `datahub` entry to `OpenLineage/compatibility-tests`.** The
  upstream cross-consumer compatibility repo at
  `github.com/OpenLineage/compatibility-tests` hosts canonical scenarios
  under `consumer/scenarios/` and per-consumer mappings under
  `consumer/consumers/<name>/`. Currently only `dataplex` is listed. The
  conceptual facet-to-entity mapping in appendix §A.3 should be
  re-expressed as `consumer/consumers/datahub/mapping.json` in the repo's
  standardized format (`mapped.core`, `mapped.<FacetName>`, `knownUnmapped`)
  and paired with a `validator/` that calls `GET /openapi/v3/entity/<type>/<urn>`
  to verify each scenario's expected DataHub aspects. That gives DataHub an
  official seat in the OL conformance matrix and a vendor-neutral regression
  target.
- **Upstream receiver-side conformance proposal.** The OpenLineage project
  versioning document (`spec/Versioning.md`) is silent on receiver
  expectations. Contributing a short receiver-side guideline based on the
  behavior this RFC ships — envelope JSON Schema validation,
  `additionalProperties`-permissive, naive-tz coercion — gives downstream
  implementations a neutral target. Natural companion to the
  `compatibility-tests` contribution above.
- **OpenLineage 2-0-3 / future versions.** Additive spec changes are absorbed
  by regenerating `openlineage.json` and adding mapping methods; no
  architectural change required.

## Unresolved questions

1. **Default DataPlatform when the orchestrator cannot be derived.** The
   proposed default is the literal `openlineage`. An alternative derives it
   from `Job.namespace` by parsing a URI scheme. Decision pending observation
   of real producer populations.
2. **DataFlow scope when `Job.name` contains no `.`.** The proposal is a
   single-task flow named after the job. An alternative uses `Job.namespace`
   as the flow id and `Job.name` as the task id. Choice affects URN stability
   for producers that do not follow the `flow.task` convention.
3. **Length of the parallel-write window for `documentationTarget` /
   `ownershipTarget`.** One minor release may be too short for sites on
   quarterly upgrade cadences. Two minor releases delays cleanup.
4. **Overlap between the existing Airflow-specific and Spark-specific
   custom-facet handlers and the standard facets.** `processAirflowProperties`
   reads `run.facets.airflow.dag.tags` for DataHub-side tag ingestion, which
   overlaps functionally with standard `TagsJobFacet` / `TagsRunFacet`. The
   proposal leaves the custom handlers in place; a follow-up RFC can audit
   them for duplication.
5. **Cross-producer dataset overwrite behavior for `DatasetEvent`.** The
   `datasetEventNamespaceByProducer` knob ships off by default. If real-world
   cross-producer collisions are observed, a later RFC flips the default.
6. **Naive-timezone `eventTime` handling — resolved.** The OpenLineage
   reference Python client emits timestamps without an offset
   (`"2021-11-03T10:53:52.427343"`) and Marquez accepts them. The
   openapi-servlet's `ObjectMapper` installs a permissive `ZonedDateTime`
   deserializer that falls back to `LocalDateTime.parse(s).atZone(UTC)`
   on `DateTimeParseException`, matching Marquez's acceptance
   unconditionally. No config knob. Hurl suite fixtures: Marquez-parity
   positives in `10_unicode_and_edge_cases.hurl` r04 / r06 / r07; the
   strict-spec alternative lives in `10_unicode_and_edge_cases_strict.hurl`
   (excluded from the pytest runner by the `*_strict.hurl` filename
   convention) for anyone who wants to test a stricter configuration.
   An upstream clarification to `spec/Versioning.md` about receiver
   expectations for naive timestamps would make the fallback redundant;
   the "Upstream receiver-side conformance proposal" in Future Work is
   the vehicle for that.

## Appendix

Per-facet mapping tables, test suite overview, methodology, the
OpenLineage / DataHub / Marquez cross-walk, and the linked issues/PRs are in
[`000-openlineage-spec-compliance-appendix.md`](./000-openlineage-spec-compliance-appendix.md).
