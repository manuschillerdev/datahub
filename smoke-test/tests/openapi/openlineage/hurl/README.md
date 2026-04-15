# OpenLineage endpoint — Hurl test suite

> **Status: exploration artifact.** This directory drove the source-level
> audit behind the RFC at
> [`docs/rfcs/active/000-openlineage-spec-compliance.md`](../../../../../docs/rfcs/active/000-openlineage-spec-compliance.md)
> and is not part of the production test strategy. The implementation PR
> lifts the fixture JSON payloads into
> `metadata-service/openapi-servlet/src/test/resources/openlineage/fixtures/`
> and deletes this entire tree along with the pytest wrapper at
> `smoke-test/tests/openapi/openlineage/test_openlineage_spec.py`. See the
> RFC's §"Test strategy" for the canonical Spring MockMvc test layer.

[Hurl](https://hurl.dev) tests for `POST /openapi/openlineage/api/v1/lineage`.
Each file targets a specific section of the OpenLineage 2-0-2 spec and a
specific row of the RFC's implementation-status appendix.

The payloads are oriented on:

- The OpenLineage `2-0-2` core spec (`OpenLineage/OpenLineage/spec/OpenLineage.json`).
- The standard facets in `OpenLineage/OpenLineage/spec/facets/`.
- Marquez's reference test fixtures
  (`MarquezProject/marquez/api/src/test/resources/open_lineage/`, Apache 2.0).

## Running

```bash
# Install hurl: brew install hurl  (or see https://hurl.dev/docs/installation.html)

# Full suite via the wrapper — generates a fresh run_id, captures a log mark,
# runs hurl, then parses docker logs and emits a per-request MCP delta.
./run.sh

# Subset:
./run.sh 02_event_types.hurl 04_producer_uri.hurl

# Clean-slate (wipes DataHub state first — slow):
./run.sh --reset

# Against a non-default container:
./run.sh --container datahub-gms

# Raw hurl without correlation (don't do this if you care about attribution):
hurl --variables-file vars.env --variable run_id=manual --test *.hurl
```

## Bulletproof per-request attribution

Every hurl request carries a unique `User-Agent` header of the form
`hurl/<run_id>/f<NN>-r<MM>-<slug>`, where:

- `run_id` is a fresh timestamp+random tag generated per `run.sh` invocation.
- `NN` is the hurl file number (01–10).
- `MM` is the 1-indexed request position inside that file.
- `slug` matches the filename minus the leading number and extension.

Example: `hurl/20260414T081433Z-e9b8fe13/f06-r04-job_facets`.

DataHub's `RequestContext` (`i.d.metadata.context.RequestContext:118`) logs the
`userAgent` verbatim on every request. `run.sh` filters `docker logs --since
<mark>` for the current `run_id` and runs `parse_gms.py`, which:

1. Groups log lines by Jetty worker thread ID.
2. Splits each thread's activity at every `LineageApiImpl:59 - Received lineage event:` marker.
3. Tags each resulting request block with the `User-Agent` from its `RequestContext` line.
4. Collects every `LineageApiImpl:93 - Ingesting MCP: …` line inside that block.
5. Classifies the block's error (if any) into a short signature.

Output is a table of `<UA tag> → <aspects emitted>`. Stale log entries from
prior invocations are safely ignored because their `userAgent` contains a
different `run_id`.

The only requests not correlated by this scheme are ones that are **rejected
before** DataHub writes its `Received lineage event` log line — e.g. Jackson
`DateTimeParseException` on a malformed timestamp. These appear in the report
as `? (no log match)` and are correctly attributed to pre-dispatch failure.

## Files

| File | Reqs | Spec area | RFC appendix row |
|---|---|---|---|
| `01_envelope_required_fields.hurl` | 15 | `BaseEvent` + `RunEvent` + `Run` + `Job` required fields, unparseable body, wrong media type, type-mismatch negatives | A.1 (envelope) |
| `02_event_types.hurl` | 11 | `RunEvent` / `JobEvent` / `DatasetEvent` dispatch + exclusion negatives + empty `inputs`/`outputs` + legacy `2-0-0/#/definitions/` schemaURL | A.1 (dispatch) |
| `03_run_state_transitions.hurl` | 10 | `RunEvent.eventType` enum (6 values + 3 negatives) | A.1 (run state) |
| `04_producer_uri.hurl` | 7 | Free-form `producer` URI positives (canonical / Airflow / Trino / custom / non-github / ProcessingEngine-driven / arn: scheme). `format: uri` negatives deferred with JSON Schema validation (RFC Future Work). | A.1 (producer) |
| `05_run_facets.hurl` | 11 | Every standard run facet | A.2 |
| `06_job_facets.hurl` | 9 | Every standard job facet | A.3 |
| `07_dataset_facets.hurl` | 22 | Every standard dataset facet, every `LifecycleStateChange` enum value, `SchemaDatasetFacet` simple/upper/rich (map/union/array/int64), `ColumnLineage` 1.0 + 1.2 + dataset-level indirect | A.4 |
| `08_input_output_facets.hurl` | 9 | Every standard input/output facet + `InputSubsetDatasetFacet` (compare/binary/location/partition) + `OutputSubsetDatasetFacet` | A.5, A.6 |
| `09_unknown_facet_tolerance.hurl` | 8 | Vendor facets on run/job/dataset/inputFacets/outputFacets/DatasetEvent + unknown top-level envelope field + unknown nested field on a known facet | RFC §7 |
| `10_unicode_and_edge_cases.hurl` | 7 | Unicode, nanosecond, non-UTC offset, 3 naive-tz positives (Marquez parity), 1 epoch-ms negative | edge cases |

**Spec coverage (OpenLineage 2-0-2):** every `$defs` event type, every `required` field on
each, every `eventType` enum value, every standard facet in `spec/facets/`, and every
`LifecycleStateChange` enum value. See the audit at `/tmp/openlineage-coverage-audit.md`
(if still around) or rerun it against `https://openlineage.io/spec/2-0-2/OpenLineage.json`.

## Suite scope vs. RFC scope

The Hurl suite encodes the full OpenLineage spec-compliance contract as TDD: it
includes positive fixtures for every standard facet, every `eventType` and
`LifecycleStateChange` enum value, and negative fixtures for every envelope
`required` field, every dispatch exclusion rule, every `eventTime` format
edge case, and `format: uri` on `producer` / `schemaURL`.

The governing RFC (`000-openlineage-spec-compliance.md`) deliberately does not
commit to request-layer JSON Schema validation. Its scope is the bug fixes,
event-type dispatch, facet routing, mapping, and a small amount of
`ObjectMapper` configuration. The subset of this suite that actually passes
post-RFC is:

- All positives that exercise dispatch and facet routing.
- Whatever Jackson catches natively against `io.openlineage:openlineage-java`
  beans: type mismatches, unknown `eventType` values, malformed `ZonedDateTime`
  (epoch-ms, garbage strings), unparseable JSON, wrong `Content-Type`.
- Naive-timezone `eventTime` positives (`10-r04` / `r06` / `r07`), via the
  permissive `ZonedDateTime` deserializer the RFC installs on the
  openapi-servlet's `ObjectMapper`. Marquez parity is the committed contract.

The rest — missing-required-field negatives, dispatch-exclusion negatives,
`format: uri` negatives — encodes behavior that depends on a future validation
layer. Those fixtures stay in the suite as a regression gate for that work,
not as a claim this RFC satisfies.

## Spec-strict sibling files (`*_strict.hurl`)

Some contracts in this suite ship relaxed by default — notably the naive-tz
`eventTime` positives in `10_unicode_and_edge_cases.hurl`, which the RFC
accepts with UTC coercion to match Marquez. The strict-spec alternative
(`format: date-time` RFC 3339, reject naive timestamps) is encoded as a
parallel `*_strict.hurl` fixture file — e.g.
`10_unicode_and_edge_cases_strict.hurl` — asserting the opposite HTTP status
on the same payloads.

`*_strict.hurl` files are excluded from the pytest runner
(`test_openlineage_spec.py` filters `*_strict.hurl` alongside `*workaround*`)
so that running the default suite against a Marquez-parity configuration
doesn't flag them as failures. They exist to pin the strict contract as
documentation and to be runnable manually via
`hurl 10_unicode_and_edge_cases_strict.hurl` if someone is testing a
stricter `ObjectMapper` configuration.

The convention generalizes: if a future contract decision ships a relaxed
default with a strict alternative, add a `<file>_strict.hurl` sibling
encoding the alternative and it's picked up by the same exclusion rule.

## Reference implementations

**OpenLineage compatibility-tests repo** (`github.com/OpenLineage/compatibility-tests`,
Apache-2.0). The OpenLineage project's own cross-consumer compatibility corpus. Layout:

- `consumer/scenarios/<name>/events/*.json` — canonical OL event payloads shared across
  consumers. Current scenarios: `simple_run_event`, `CLL`, `airflow`,
  `spark_dataproc_bigquery_shakespare`, `spark_dataproc_simple_producer_test`,
  `spark_dataproc_simple_producer_test_complete`. Each scenario ships a
  `scenario.md` describing what the events represent and a `config.json` tagging
  which facets and which producer version they exercise.
- `consumer/consumers/<name>/mapping.json` — per-consumer "OL event → consumer API
  entity" mapping in a standardized JSON format (`mapped.core`, `mapped.<FacetName>`,
  `knownUnmapped`). Currently the repo has one consumer entry: `dataplex`. This is
  the upstream home for the conceptual facet-to-entity mapping documented in RFC
  appendix §A.3 — contributing a `datahub/` consumer entry is tracked as RFC Future
  Work.
- `consumer/consumers/<name>/scenarios/<scenario>/validation/` — expected per-consumer
  state after ingesting each scenario, paired with a `validator/` directory holding
  consumer-specific validation logic.

Our Hurl suite's positive fixtures already cover the shapes exercised in
`simple_run_event` (canonical minimal RunEvent → our 01-r01), `CLL` (ColumnLineage
1.2 with transformations → 07-r03 / 07-r22), and the `spark_dataproc_*` scenarios
(Schema, Datasource, ProcessingEngine, JobType → 07-r01, 07-r02, 05-r03, 06-r06 /
06-r08). The compatibility-tests corpus is small (six scenarios, handful of events
each) and its role is cross-consumer conformance, not exhaustive negative-path
testing. Lifting individual payloads is the kind of thing a GitHub-sync job would
do if we wanted automatic drift detection; for now the suite encodes the same
contract independently. Upstream contribution of the DataHub consumer entry is the
bigger win, not importing their corpus.

**OpenMetadata** has its own OpenLineage receiver at
`openmetadata-service/src/main/java/org/openmetadata/service/resources/lineage/OpenLineageResource.java`
with an integration test at `openmetadata-integration-tests/.../OpenLineageResourceIT.java`
(~21 JUnit tests, Apache-2.0). Its receiver accepts **only** `RunEvent` (built on a
hand-forked schema rather than `io.openlineage:openlineage-java`), and the test suite
is strictly happy-path: no `required`-field negatives, no `eventType` enum negatives,
no dispatch-exclusion tests, no unicode/timezone edge cases, no `LifecycleStateChange`
coverage. Useful ideas to adopt if the feature surface grows: batch endpoint
partial-success semantics, run-lifecycle sequence as a single test, feature-flag-disabled
503 path. None apply to the current DataHub endpoint without extending the feature
surface.

## Status

The assertions in this suite encode the **post-RFC** contract. Several files
will currently fail against `master` because the issues listed below are still
open. Each failing assertion is annotated with the issue number it tracks, so
running the suite against `master` is itself a regression report.

| Currently failing | Tracking issue |
|---|---|
| `02_event_types.hurl` — JobEvent | datahub-project/datahub#15196 |
| `02_event_types.hurl` — DatasetEvent | (no dispatch path exists) |
| `04_producer_uri.hurl` — custom producer | datahub-project/datahub#16961 |
| `04_producer_uri.hurl` — Trino built-in listener URL | datahub-project/datahub#13011 |
| `06_job_facets.hurl` — TagsJobFacet, OwnershipJobFacet | datahub-project/datahub#14458 |
| `06_job_facets.hurl` — JobTypeJobFacet, SourceCodeLocationJobFacet | RFC milestone A |
| `07_dataset_facets.hurl` — DocumentationDatasetFacet | RFC milestone A |
| `08_input_output_facets.hurl` — OutputStatistics | RFC milestone A |
| `09_unknown_facet_tolerance.hurl` | RFC §7 (debug log instead of 500) |

## Conventions

- Every file is self-contained: it sets all its own variables and does not
  depend on prior request side effects.
- `runId` and `eventTime` are pinned to deterministic values (UUIDv4 string
  literals, `2026-04-14T...` timestamps) so fixtures are reproducible across
  runs.
- Authentication uses the `{{token}}` variable. `vars.env` defaults it to the
  empty string for the unauthenticated dev profile; override on the command
  line for authenticated environments.
- Assertions use `HTTP 200` (the post-RFC happy path) or `HTTP 400` (the
  post-RFC validation failure path). HTTP 500 is never an expected outcome and
  is always a bug.
