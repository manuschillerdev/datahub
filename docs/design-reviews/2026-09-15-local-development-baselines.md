# Local development performance: current state

Last updated: 2026-09-16. This is the canonical report for the investigation branch
`perf/local-dev-investigation`, including implementation status, measurements, remaining bottlenecks
and decisions. The earlier investigation and modes documents have been superseded.

## Management summary

The largest retained measured gains come from smaller Docker contexts and native Java
development servers. The custom Docker skip guard has been removed; builds use native caching.
Production GMS artifact ownership, frontend build-context staging,
and batched Java push hooks are now implemented in the working tree and measured.
Frontend install-state tracking and duplicate GraphQL generation are fixed, but their standalone
wall-clock gains have not been established. Yarn remains the repository package manager; neither
pnpm nor Redpanda has been adopted.

| Execution mode                              | Bottleneck                                                 | Implementation status                 | Applied fix                                                      | Measured baseline                                                 | Improved value                                             | Relative improvement                                         |
| ------------------------------------------- | ---------------------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------ |
| Docker debug: unchanged start               | Repeated image-build orchestration                         | Historical guard removed              | Now uses native Docker caching; see follow-up below              | 94.01 s                                                           | Historical guard: 9.99 s                                   | Historical 89.4%; current startup not remeasured             |
| Docker debug: GMS edit                      | Broad Gradle graph                                         | Implemented                           | Select owning image module; retain shared/unmapped fallback      | ~17 s build phase; 258 tasks                                      | ~11 s; 229 tasks                                           | ~35% build time; ~11% fewer tasks                            |
| Docker vs host Play                         | Java compile/stage/container restart                       | Implemented                           | Play development reload compiler                                 | 15.69 s Docker median                                             | 6.27 s host median                                         | 60.0%                                                        |
| Docker vs host Play                         | Route compile/stage/container restart                      | Implemented                           | Play development reload compiler                                 | 17.56 s Docker median                                             | 5.31 s host median                                         | 69.8%                                                        |
| Docker vs host GMS                          | Method edit compile/package/JVM restart                    | Implemented                           | Continuous compilation plus Spring DevTools                      | 34.56 s Docker median                                             | 14.23 s host median                                        | 58.8%; Docker warm-up trend                                  |
| Docker vs host GMS                          | Structural edit compile/package/JVM restart                | Implemented                           | Continuous compilation plus Spring DevTools                      | 31.24 s Docker median                                             | 14.32 s host median                                        | 54.2%                                                        |
| Gradle frontend checks                      | Fingerprinting the dependency tree                         | Implemented; warm A/B incomplete      | Track manifest/lockfile and `.yarn-integrity`                    | Full-tree first snapshot interrupted after >6 min; no warm median | 3.15 s warm marker median                                  | Not established for comparable warm states                   |
| Production frontend build                   | GraphQL generated twice                                    | Implemented; gain unquantified        | Gradle calls Vite-only script after its cacheable generator      | Two generation paths; no isolated time                            | One generation path                                        | Time saving not measured                                     |
| All Gradle modes, linked worktrees          | Incorrect Git metadata and potential artifact invalidation | Implemented correctness fix           | Worktree-aware plugin and lazy worktree-rooted Git describe      | Wrong primary-worktree HEAD reproduced                            | Correct worktree HEAD/description verified                 | Speed gain not measured                                      |
| Production Docker: GMS                      | WAR COPY followed by recursive ownership change            | Implemented                           | Create/own directories before artifact COPY; COPY with ownership | 25.39 s fresh-WAR observation; two ~694 MB layers                 | 20.72 s; one WAR layer                                     | 18.4%; one clean pair. Docker-reported image size down 45.8% |
| Production Docker: Play frontend            | Worktree context processing despite cached layers          | Implemented                           | Gradle stages artifact-only production context                   | 17.42 s cached-image median                                       | 0.48 s image; 3.46 s including separate warm preparation   | 97.2% image-only; conservative pipeline 80.1%                |
| Production Docker: frontend artifact change | Context work plus image export/load                        | Implemented                           | Same staged context; preparation included in pipeline            | 34.91 s median of two fresh-layer observations                    | 19.28 s image; 24.97 s including preparation               | 44.8% image-only; pipeline 28.5%; two pairs                  |
| Initial frontend setup                      | Dependency installation                                    | pnpm experiment only                  | No repository migration                                          | Successful Yarn baseline missing                                  | pnpm: 112.01 s cold observation; 60.52 s warm-store median | Yarn-to-pnpm gain not established                            |
| Infrastructure Docker                       | Broker startup/resource use                                | Redpanda not tested                   | None                                                             | Kafka startup snapshot ~530 MiB / ~111% CPU                       | Not measured                                               | Not measured                                                 |
| Push hooks                                  | Repeated Java Gradle launches                              | Implemented                           | One serial hook batches every matching parent/child project task | Nested Java 6.26 s median; two Java launches                      | 3.21 s; one Java launch                                    | 48.7%; single Java/mixed scenarios effectively unchanged     |
| Host GMS                                    | Hazelcast Kubernetes discovery during restart              | Profiled; fix not implemented         | None beyond host mode                                            | 9.89 s isolated restart median; ~5.20 s Hazelcast startup         | Not measured                                               | Discovery accounts for ~53% of isolated restart latency      |
| Gradle                                      | Configuration-cache incompatibility                        | Deferred                              | Cache remains disabled                                           | Representative graph reports 144 problems and discards entry      | Estimated 1–3 s saving per repeated invocation             | Estimated 7–21% of 14.23 s GMS loop; not measured            |
| Host GMS                                    | Worker-count limit                                         | Experiment rejected; override removed | Repository default remains two workers                           | Two workers: 7.03, 5.90 s                                         | Six: 5.57 s; twelve: 5.90, 5.56 s                          | No reliable relevant gain                                    |

Rows use different boundaries and are not additive. Host-mode comparisons use the already narrowed
Docker path; their percentages are not additional independent savings on the earlier broad graph.

## Execution modes and setup

All environment operations use `scripts/dev/datahub-dev.sh`.

| Mode                   | Entry point after setup                       | Host processes                                  | Docker processes                    | Reload behavior                                                               |
| ---------------------- | --------------------------------------------- | ----------------------------------------------- | ----------------------------------- | ----------------------------------------------------------------------------- |
| Full Docker debug      | `start`; `rebuild --wait` after edits         | Gradle compilation/packaging                    | Applications and infrastructure     | Artifact rebuild, service restart, readiness wait; no automatic source reload |
| Docker plus Vite       | `frontend` after `start` and `setup frontend` | React/Vite                                      | Play, GMS and remaining environment | React HMR; backend still rebuilds/restarts                                    |
| Host GMS               | `gms` after `start`                           | GMS `bootRun` and continuous Gradle compiler    | Infrastructure and other services   | DevTools context restart on compiled changes, including structural edits      |
| Host Play              | `play` after `start`                          | Play development server; optional separate Vite | GMS and remaining environment       | Java/Scala/routes reload compilation; React uses Vite separately              |
| Production-like Docker | Production image/deployment workflow          | Artifact builds when performed locally          | Applications and infrastructure     | Image and container rebuild; packaging/integration validation, not hot reload |
| Docs development       | `docs`; `docs --build` for regeneration       | Docusaurus                                      | Not required for docs server itself | Docs-site development server; generation is separate from ordinary editing    |

One-time `setup` prepares the Python ingestion environment; `setup frontend` installs frontend
dependencies. Initial `start` can include code generation, GMS archives, Play staging, React assets,
Actions and upgrade images, Bake preparation, Compose initialization and readiness. A fully cold
start also downloads tools/dependencies/images and initializes persistent storage. No controlled
end-to-end cold-start baseline exists.

Docker debug mounts built Java artifacts and uses staged Play `ProdServerStart`, not Spring DevTools
or Play development mode. JDWP allows IDE-driven limited JVM HotSwap, but is not an automatic reload
workflow. Actions mounts Python source without a watcher. Host consumer and watched Actions modes
have not been implemented. Vite HMR already existed before this investigation.

Host Java commands precompile before replacing their corresponding healthy Docker service, translate
worktree ports and dependency endpoints, and restore that service on exit/failure. Host Play excludes
production React assets, disables configuration on demand only for its incompatible plugin graph,
and explicitly supplies the generated Rest.li client jar. Host GMS disables Fabric8 Kubernetes
auto-configuration only for `bootRun`, avoiding local kubeconfig credential-helper stalls.

The current launcher shares container handover, process supervision and cleanup between Play and
GMS rather than maintaining separate implementations. Fixed GMS development settings (server port,
registry resource path, internal schema-registry URL and DevTools enablement) are declared in the
existing `bootRun` host-development block; Play's development MFE setting is declared in `playRun`.
No new user-facing settings or profiles are added. The GMS continuous compiler and readiness gate,
worktree endpoint translation, precompilation and Docker restoration are retained. Earlier timing
results describe the original launcher; this refactoring is not a new performance comparison.
The refactoring removes 63 net Python lines and adds five Gradle configuration lines. Smoke checks
confirmed GMS HTTP readiness on port 9080, its matching internal schema-registry URL and continuous
compiler launch; Play returned HTTP 200 from `/health` on port 10002 and loaded
`conf/mfe.config.dev.yaml` through its development settings. Both wrappers restored their Docker
services on exit, and the complete environment reported healthy. Python lint/format checks passed;
no source-edit timing matrix or new tests were added for this refactoring.

The repository supports optional mise bootstrap, not mandatory mise execution. Java 25 compatibility
is required regardless of tool manager. Host Java modes use the caller's configured environment;
hardcoded `mise exec` was removed. Investigation commands use mise for controlled tool versions.
Gradle already enables its daemon, parallel execution, build cache and configuration on demand, with
two workers and a two-GiB default daemon heap. These defaults remain unchanged.

## Applied changes

| Commit       | Current effect                                                                                                                                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `174b5ea7b3` | `yarnInstall` inputs are `package.json`/`yarn.lock`; output is `node_modules/.yarn-integrity`. Gradle production build uses Vite-only scripts after GraphQL generation; standalone `yarn build` retains generation. |
| `ceca43d1aa` | Debug image guard subsequently removed, including Git fingerprinting and metadata/tag validation. Local debug provenance/SBOM remain disabled; CI/Depot unchanged.                                                  |
| `2bea0e8d84` | Service rebuilds select owning Gradle image modules with full-profile fallback for shared/unmapped changes. Gradle still runs on a Git-clean tree because reverted source can leave stale artifacts.                |
| `dfdb81effa` | Adds worktree-aware host Play and GMS development modes, reload behavior and Docker service restoration.                                                                                                            |
| `4d1e9cdac3` | Removes hardcoded mise execution from host Java modes, preserving optional bootstrap.                                                                                                                               |
| `66ce33b1fe` | Upgrades Git-properties plugin 2.5.3 to 4.0.1 and uses lazy Git describe rooted in the linked worktree. Forced output matches worktree HEAD and description.                                                        |
| `95ac6ee5f5` | Removes the unproven worker tuning introduced by `7119b52481`; no adaptive worker policy remains.                                                                                                                   |

### Current implementation

- GMS user and writable directories are created before production artifacts. All application COPY
  operations set `datahub` ownership; no later operation recursively changes the WAR's ownership.
- `datahub-frontend:prepareDockerContext` is a declared-input/output Gradle `Sync` task depending on
  `stage`, retaining only runtime script, startup/configuration files and staged distribution inputs.
  Production/debug Bake and `docker` use `datahub-frontend/build/docker-context`;
  `dockerFromCache` retains the worktree context because it skips preparation. Debug Bake reuses
  the existing staging dependency. The context adds approximately 626 MiB of generated disk use and is rebuilt when
  its inputs change; warm unchanged preparation is up to date.
- The hook generator emits one serial Java hook with filenames. Its stdlib Python runner selects all
  matching module-wide Spotless tasks, including both parent and child tasks, and invokes Gradle once.
  Coverage matches all 61 original Java projects and 4,923 tracked Java files. All non-Java hook
  definitions remain unchanged.

## Java feedback measurements

Measurements used revision `dfdb81effab544d51eb6646c80ea7fffe8daab50`, Apple arm64 with 12 CPUs and
64 GiB RAM; Colima had 4 CPUs, 32 GiB RAM, a 95 GiB disk and VirtioFS. Java was 25.0.2.
Caches, generated outputs, images and volumes were retained. Discarded primers preceded five unique
edits per scenario, preventing build-cache reuse of alternating source states. Counted runs verified
unique HTTP response markers; temporary probes were removed and Docker services restored.

| Scenario       | Docker samples (s)                | Docker median | Host samples (s)                  | Host median |
| -------------- | --------------------------------- | ------------- | --------------------------------- | ----------- |
| Play Java      | 15.52, 15.77, 15.70, 15.69, 15.58 | 15.69 s       | 7.12, 6.51, 6.26, 6.05, 6.27      | 6.27 s      |
| Play routes    | 17.56, 17.50, 18.80, 17.94, 17.01 | 17.56 s       | 5.69, 5.25, 5.40, 5.14, 5.31      | 5.31 s      |
| GMS method     | 38.01, 39.18, 34.56, 29.65, 29.76 | 34.56 s       | 14.33, 14.13, 14.11, 14.23, 14.37 | 14.23 s     |
| GMS structural | 31.72, 31.24, 31.54, 30.91, 31.10 | 31.24 s       | 14.73, 14.28, 14.44, 14.16, 14.32 | 14.32 s     |

Host GMS compilation medians are 5.07 s for methods and 5.01 s for structural edits; restart/readiness
medians are 9.09 s and 9.35 s. Phase medians need not sum to the total median. Stable Docker GMS
structural runs execute seven of 229 tasks, spend 11–12 s in Gradle and approximately 18 s reaching
readiness. The Docker method series retains a downward warm-up trend. Initial host HTTP readiness
can precede the continuous compiler's explicit watch-ready output; steady-state edit detection works.

The unchanged Docker start comparison is one observed 94.01 s versus 9.99 s pair, not a multi-run
median. Recovery and new-task-model priming runs are not included. Incorrect JDK and linked-worktree
Git metadata contaminated discarded benchmark runs, not the reported samples.

## GMS restart profile

On 2026-09-15, the current investigation worktree was profiled using Java 25.0.2 and the existing
`datahub-dev gms` mode on its assigned port, 9080. Initial compilation, code generation, first boot
and continuous-compiler initialization were excluded. Concurrent Gradle work from another worktree
had ended before the counted restarts. No application source or tests were changed.

Each probe touched the existing compiled `GMSApplication.class`, without changing its bytecode.
Completion required a new DevTools restart, a new `Started GMSApplication` log and HTTP 200 from
`/health`, with a 45-second deadline. This isolates class-change detection and restart from source
compilation; it does not replace the earlier unique-source-edit feedback measurements.

| Boundary / component                          | Observations                                              | Interpretation                                                                                     |
| --------------------------------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Class touch to confirmed restart/readiness    | 9.69, 9.89 s with JFR; 10.08 s without JFR; median 9.89 s | Reproduces the remaining restart cost; small sample, not an optimization comparison                |
| Spring application startup, reported by Boot  | 7.979, 7.759, 7.645 s                                     | Includes Hazelcast and other application initialization                                            |
| Hazelcast lifecycle STARTING to STARTED       | 5.203, 5.198, 5.196 s                                     | Consistent ~5.20 s block on the startup critical path                                              |
| Startup-thread parking in Hazelcast discovery | 5.177, 5.174 s in the two JFR runs                        | Direct attribution, not an inference from a log gap                                                |
| Remaining class-touch-to-ready time           | ~4.5–4.9 s after subtracting Hazelcast lifecycle duration | Other startup, shutdown, detection and readiness observation combined; not independently optimized |

The dominant cause is Kubernetes discovery in `CacheConfig.hazelcastInstance`: it unconditionally
enables Hazelcast Kubernetes discovery and uses `searchService.cache.hazelcast.serviceName`, whose
default is `hazelcast-service`. In host development that DNS name does not resolve. Every counted
restart repeatedly logs failed DNS lookups before forming a one-member cluster. JFR shows
`restartedMain` parked in `BackoffIdleStrategy.idle` under
`DiscoveryJoiner.getPossibleAddressesForInitialJoin` and `TcpIpJoiner.joinViaPossibleMembers`.
This accounts for approximately 53% of the isolated restart median. The DevTools relaunch thread's
~8-second `Thread.join` waits for application startup; it must not be counted again as shutdown time.

The next targeted experiment is explicit standalone Hazelcast discovery for local host development,
while keeping the embedded instance, maps and serializers, and preserving production Kubernetes
discovery. Changing only the search cache to Caffeine is insufficient: entity graph caching and other
enabled coordination features can still require Hazelcast. Standalone mode would not be appropriate
for testing cross-service or multi-instance coordination. No discovery change has been implemented
or measured. Removing the observed wait could save roughly five seconds per restart, approximately
35% of the previously measured 14.23-second host method-edit loop; that is an estimate, not an A/B
result.

The recording was stopped and the host wrapper exited cleanly, restoring Docker GMS. The restored
environment reported GMS and frontend healthy with HTTP 200. Profiling added no permanent runtime
instrumentation, application changes or tests.

## Configuration cache: deferred

Configuration cache is disabled and optional; incompatibility does not break the normal build.
Deleting cache state cannot repair task-model incompatibility. The representative GMS classes trial
reports 144 problems and discards its entry. Counts vary with task selection and exclusions.

The required changes are shared Pegasus actions/predicates that capture `Project`/`SourceSet`,
execution-time project access including Avro namespace inputs, resource-filter/copy closures,
a build-finished listener, configuration-time Git processes, and version-file writes during
configuration. Fixing them requires declared task inputs, serializable actions/predicates,
provider-based process results, a lifecycle service/task and a declared version-file generation task.
The vendored build plugin is `vendor/rest-li-fork/gradle-plugins-29.74.2-gradle9.jar`; runtime/codegen
dependencies remain Maven artifacts. Its documented fork source was inaccessible (HTTP 404), with
no usable local source checkout, so reproducible plugin modification is currently blocked.

Estimated reusable-cache savings are 1–3 s per repeated Gradle invocation, not measured results.
For host GMS that would reduce the ~5.1 s compile phase to ~2.1–4.1 s and the 14.23 s method loop
to ~11.23–13.23 s (7–21%); the ~9 s Spring restart remains. For the current 3.15 s warm frontend
check, an illustrative 1–2 s saving would leave ~1.15–2.15 s, but configuration time has not been
isolated from startup/fingerprinting. These savings overlap and are not additive.

The uncertain few-second gain does not justify fork refactoring, rebuilding and integrity updates,
versioning changes, and cross-graph invalidation validation in this optimization effort.
Configuration-cache work is deferred unless profiling establishes materially larger savings or
maintainers undertake reproducible plugin compatibility work. Worker tuning is likewise not pursued:
its small samples and warm-up trend did not establish a relevant gain.

## Scope and protocol

The upstream starting point was verified as the then-current `datahub-project/datahub:master` at
`6ece48b05a2a260e6c9df8aec4be5f7f1e7deca6`; optimization commits descend from it. This is provenance,
not a claim of identity with today's moving upstream master.
The investigation HEAD at measurement time was `95ac6ee5f5`. Latest Docker/context and Java hook
comparisons included worktree fixes that are now committed in this branch; earlier installation and
fingerprint measurements use that measurement-time HEAD before those fixes. These measurements do
not represent a fresh checkout of upstream master. Commands run sequentially on
the same Apple Silicon host through mise. Gradle uses Java 25, its existing daemon and downloaded
Node 22.16.0. Direct installation comparisons use Node 22.23.2, Yarn 1.22.22 and pnpm 9.12.2.
Docker Engine is 28.4.0 on aarch64 via Colima. Existing Docker infrastructure remains running.

Unless otherwise noted, warm scenarios use a discarded primer and three timed samples. Wall times include command startup.
Failures and interrupted runs are not included in medians. These small samples establish practical
baselines, not statistical confidence. No application tests are added or changed, no commits or
pushes are performed, and benchmark image tags do not replace the running services' images.

## Commit and push hooks

Markdown/MDX, workflows, GraphQL, PDL, Python and other checks already have file/path filters.
Markdown formatting is not unconditional. Betterleaks intentionally checks every commit's staged
diff. The >500-file push guard runs after formatters and takes a missing-ref path when refs are
unavailable. Neither security checks nor existing formatting coverage has been removed.

The actual pre-commit 4.3.0 runner executes the repository configuration with explicit filenames,
`--verbose`, and each of `--hook-stage pre-commit` and `--hook-stage pre-push`. Its tool environment
is managed by `uv tool run`. Primers include any first-use environment setup; measured runs do not.

| File scenario                  | Commit median | Current push samples | Current push median | Current push Gradle invocations |
| ------------------------------ | ------------- | -------------------- | ------------------- | ------------------------------- |
| Markdown                       | 0.35 s        | 4.08, 3.89, 3.93 s   | 3.93 s              | 1                               |
| Java, Play frontend            | 0.28 s        | 3.38, 3.42, 3.41 s   | 3.41 s              | 1                               |
| Java, nested generator project | 0.28 s        | 3.21, 3.25, 3.15 s   | 3.21 s              | 1                               |
| Python                         | 0.58 s        | 0.51, 0.52, 0.48 s   | 0.51 s              | 0                               |
| Markdown + Java + Python       | 0.64 s        | 7.36, 7.54, 7.47 s   | 7.47 s              | 2                               |

Commit, Markdown-only and Python-only values are retained baselines: their hook definitions did not
change. Java/nested/mixed push samples are current batched-hook measurements. Paired old-hook push
medians on the same files were 3.38 s, 6.26 s and 7.46 s respectively. The nested comparison improves
48.7%; the single Java and mixed differences are within noise. Mixed files still invoke Markdown
Gradle formatting separately. The nested comparison uses a clean discarded primer and three paired
samples. Before/after configurations preserve all checks; only Java launch orchestration changes.

Representative files:

- This investigation's Markdown decision document.
- `datahub-frontend/app/client/AuthServiceClient.java`.
- `metadata-service/openapi-entity-servlet/generators/src/main/java/io/datahubproject/CustomSpringCodegen.java`.
- `metadata-ingestion/src/datahub/errors.py`.

All counted samples passed. The nested Java case runs both servlet and generator Spotless tasks
inside one Gradle process. No formatter or security guard was removed.

Limitations: explicit-file runs measure hook selection and execution on existing files, not the full
Git commit/push workflow. Betterleaks scans an empty staged diff in these runs. The file-count guard
has no push refs and exits through its missing-ref path. These are not baselines for large staged
secret scans or the >500-file rejection path. No security guard is disabled.

## Frontend output fingerprinting

The current marker model retains manifest/lockfile inputs and tracks `.yarn-integrity`. An isolated
Gradle init script reintroduces the complete `node_modules` directory as an additional output, without
changing repository build files. Build cache is disabled for both variants; the install task is
already non-cacheable. Failed init-script setup attempts are excluded.

| Scenario                                        | Samples                                 | Result                                               |
| ----------------------------------------------- | --------------------------------------- | ---------------------------------------------------- |
| Current marker model, warm unchanged invocation | 3.15, 3.32, 3.11 s                      | Median 3.15 s; all tasks up to date                  |
| Reintroduced full-tree model, first snapshot    | Interrupted after more than six minutes | Lower bound only; no completed timing or warm median |

Two thread snapshots, approximately 56 and 139 seconds into the full-tree task work, show Gradle
`DefaultOutputSnapshotter`, `DirectorySnapshotter` and `DefaultFileHasher` reading and hashing files.
No Yarn installer process was running. No completed full-tree steady-state comparison is available. This demonstrates a costly first-snapshot path on this host, but does not establish a
steady-state percentage improvement: the output model changed and Gradle needed a new tree snapshot.
Warm retained-snapshot behavior remains unmeasured for the full-tree variant.
The measured dependency directory contains approximately 150,554 files according to
`rg --files --hidden --no-ignore node_modules`.

## Dependency installation

Package manifests and lockfiles are copied into temporary projects; the
existing frontend dependencies and developer caches are untouched. The first Yarn attempt uses an
empty explicit cache; the separate corrected primer uses the existing developer cache.
pnpm import is timed separately; pnpm installs use an isolated store and strict peer checking is
disabled for the comparison. These are dependency installation measurements, not frontend build,
codegen, lint or test compatibility validation.

| Scenario                                                             | Time                  | Outcome                                                                                                          |
| -------------------------------------------------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Yarn, empty explicit cache and empty project dependencies            | 433.70 s              | Failed downloading `@mui/icons-material@5.16.9` with `ESOCKETTIMEDOUT`; no successful installation baseline      |
| pnpm lockfile import                                                 | 21.34 s               | Completed with peer-dependency warnings; migration step, excluded from installation timings                      |
| pnpm, empty explicit store and empty project dependencies            | 112.01 s              | Successful; single cold-store observation                                                                        |
| pnpm, populated explicit store and empty project dependencies        | 60.52, 60.55, 52.70 s | Median 60.52 s; all successful, zero package downloads                                                           |
| Yarn, existing developer cache, corrected repository network timeout | 600.41 s              | Cache-completion primer hit the ten-minute process limit while linking; no measured successful warm-cache sample |

The failed Yarn attempt used a 60-second network timeout rather than the repository's 300 seconds.
It is therefore not a valid measurement of normal development setup, and must not be used to compute
a Yarn-to-pnpm speedup. Remaining queued fetches were stopped after the failure. Warm-cache Yarn
measurements were attempted separately using the existing developer cache and the repository timeout,
not the incomplete isolated cache. A reliable controlled cold-cache Yarn baseline remains missing.

The corrected Yarn primer reaches linking without the earlier download failure, but linking takes
several minutes. A one-second process sample shows libuv filesystem worker threads predominantly in
kernel `open` calls, with the main event loop waiting for I/O. This points to filesystem work during
linking on this host, not package resolution; it does not identify the underlying cause of slow
file operations. A recursive developer-cache size inspection overlapped part of this primer, so it
is excluded from controlled timings. It then hit the ten-minute hard process limit, so the planned
controlled fresh-project warm-cache sample was not started. Further repetitions were stopped. This
is a failed, bounded setup observation, not a successful warm-install baseline or proof of an
intrinsically broken repository setup. No completed Yarn-to-pnpm speedup can be calculated.

## Docker image builds

Image comparisons use `docker buildx build --load --progress=plain --provenance=false --sbom=false`
with `APP_ENV=prod` and the same pinned Wolfi base digest
`sha256:9a8d954d8f03a21bcf2be73d4628f0ad26d35c3275469925de63a34eebd58f13`.
Runtime layers are primed and cached during counted runs. Measurements isolate context preparation,
image evaluation, layer execution/export and load, not application compilation or service readiness.

| Current comparison                                      | Before                                | After                                      | Improvement / sample boundary                               |
| ------------------------------------------------------- | ------------------------------------- | ------------------------------------------ | ----------------------------------------------------------- |
| GMS fresh WAR resource: image build/load                | 25.39 s                               | 20.72 s                                    | 18.4%; one clean pair                                       |
| Frontend cached image: worktree vs prepared context     | 19.67, 17.42, 16.15 s; median 17.42 s | 0.51, 0.40, 0.48 s; median 0.48 s          | 97.2%; discarded primers, three alternating-order pairs     |
| Separate warm frontend context preparation invocation   | Not needed for worktree build         | 3.22, 2.93, 2.98 s; median 2.98 s          | All tasks up to date; includes Gradle startup/configuration |
| Cached frontend pipeline including separate preparation | 17.42 s                               | 3.46 s                                     | Conservative 80.1%; sum of image/preparation medians        |
| Frontend fresh staged-resource image build/load         | 34.48, 35.34 s; median 34.91 s        | 20.08, 18.48 s; median 19.28 s             | 44.8%; two fresh-layer pairs                                |
| Frontend changed-resource context preparation           | Not needed for worktree build         | 4.93, 6.45 s; median 5.69 s                | Sync executed; includes Gradle startup/configuration        |
| Changed frontend pipeline including preparation         | 34.91 s                               | Pair totals 25.01, 24.93 s; median 24.97 s | 28.5%; two pairs                                            |

The clean GMS pair uses a copied WAR and independent small resource changes for each variant. Both
upload approximately 693.68 MB (3.6 s before, 3.4 s after); the second variant cannot reuse the first
variant's uploaded artifact. Context-upload reuse is excluded from the ownership comparison.
Image history confirms removal of the duplicate approximately 694 MB recursive-chown layer.
Docker-reported image size is 1,397,990,301 bytes before and 757,940,566 bytes after (45.8% lower);
this is not a claim of equivalent physical host-disk reclamation.

Frontend cached pairs use identical staged file contents at both context roots, confirmed with
directory comparison. Worktree timings retain a downward warm-up trend. Changed probes use distinct
small resource contents for each variant so both COPY/export paths are fresh; shared runtime layers
stay cached. A reused-layer pair is excluded, leaving two valid pairs. Preparation timings exclude
`stage` to isolate context staging from already established artifact compilation/packaging costs.
The normal task depends on `stage`; production build correctness does not rely on that exclusion.
Sync adds a copy of the staged distribution on input changes. Initial preparation reported an 11 s
Gradle build; no isolated cold-copy or full cold-production pipeline baseline exists.

The separate preparation invocation is a conservative workflow accounting: normal Gradle Docker/Bake
builds perform preparation in their existing invocation, rather than launching Gradle twice.
The timings above are not full `datahub-dev start` or edit-to-ready measurements. Raw
`docker buildx build ... .` and `dockerFromCache` retain the worktree context; the measured frontend
context fix is used by production Gradle Docker/Bake workflows.

A Dockerfile-specific allowlist experiment produced similar context costs with a strong warm-down
trend (before median 19.42 s, after 15.69 s). It did not establish a reliable benefit and was removed;
only artifact-context staging remains implemented.

Other established pre-fix baselines remain useful for unmeasured boundaries:

| Scenario                                                  | Baseline                     | Limit                                                              |
| --------------------------------------------------------- | ---------------------------- | ------------------------------------------------------------------ |
| GMS debug / production fully cached image                 | 0.51 / 0.52 s medians        | Ownership fix does not have a new repeated cached-image comparison |
| Frontend debug fully cached image                         | 0.52 s median                | Debug context behavior remains unchanged                           |
| GMS changed WAR in copied narrow context                  | 28.68 s median               | Earlier pre-fix baseline, not the clean pair's denominator         |
| Frontend production cached worktree context               | 19.55 s median               | Earlier baseline; latest paired denominator is 17.42 s             |
| Frontend changed staged resource in copied narrow context | 17.34 s, two-sample median   | Earlier context root differs; not an A/B denominator               |
| GMS runtime layer invalidation                            | 88.20 s observation          | Cleanup overlap; no clean runtime-dependency baseline              |
| GMS / frontend debug runtime primers                      | 67.82 / 60.47 s observations | Cache misses/priming, not fully cold or steady-state baselines     |

## Remaining work and measurement gaps

The valid completed baselines cover cached Docker image builds, production artifact-layer changes,
pnpm installation, scoped commit/push hooks and current marker-based warm Gradle installation checks.
The GMS ownership layer, production frontend context and overlapping Java hook fixes are implemented
and measured above. pnpm conversion/build compatibility and the Redpanda experiment remain paused
at the user's request; no package-manager or broker migration is implemented.

Still unresolved: a successful controlled cold-cache and warm-cache Yarn install, a completed
full-tree warm fingerprinting comparison, and a clean runtime-layer invalidation baseline without
cleanup overlap. The interrupted/failing observations are retained to make those limits explicit.
Source compilation and readiness are measured in the Java feedback comparison, not isolated by the
image/hook matrix. Large staged secret scans and >500-file push rejection have no dedicated baseline.

| Priority / workflow        | Next change or experiment                     | Required comparison                                                                       | Status                                                                    |
| -------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Production GMS image       | COPY ownership fix complete                   | Repeated fresh-artifact runs if greater precision is needed                               | Implemented; one clean pair and ownership/image-size checks passed        |
| Production frontend image  | Artifact-only context complete                | Full production Gradle pipeline and cold context creation remain unmeasured               | Implemented; warm and changed-artifact image/preparation results recorded |
| Java push hooks            | Batched project selection complete            | Large file sets and full push-ref workflows remain unmeasured                             | Implemented; task coverage preserved, nested launch savings measured      |
| Frontend setup             | Scoped pnpm evaluation                        | Successful Yarn baseline and build/codegen/CI compatibility                               | Paused by request; incomplete installation experiment only                |
| Infrastructure startup     | Redpanda comparison                           | Broker/DataHub readiness, resource use, event-flow and persistence compatibility          | Paused by request; not started                                            |
| Host GMS iteration         | Evaluate local standalone Hazelcast discovery | Same unique-edit probes and HTTP readiness boundary; preserve required Hazelcast features | Restart profiled; ~5.2 s discovery wait identified; fix not implemented   |
| Initial setup / cold start | Establish bounded cache-state protocol        | Explicit tool/package/Docker/data cache retention and end-to-end readiness                | No complete baseline                                                      |

Kafka currently runs as one Confluent 8.2.2 KRaft broker with a 512-MiB heap, not Kafka plus
ZooKeeper. GMS serves the schema-registry endpoint. Redpanda compatibility must preserve internal/
host advertised listeners, topic initialization, five-MiB message support, health checks and event
consumers/producers. The ~530 MiB / ~111% CPU broker reading is a startup snapshot only; no baseline
for steady-state resource use or a Redpanda replacement exists.

## Validation and evidence

Implemented host modes reached HTTP 200 on Play `/admin` and GMS `/health`, and counted edit runs
verified changed responses. Git-properties forced generation matches the active linked worktree.
All counted explicit-file hook runs passed. pnpm installation success does not establish application
build compatibility. No configuration-cache implementation was made. New production GMS image checks confirm the non-root
user, writable WAR/directories and plugin resources, and executable startup script. The GMS debug
image also builds. Frontend image checks confirm its executable server/startup script and required
configuration files. The initial Bake/CLI definitions used the prepared production context and original
debug context; the native-cache follow-up below also stages debug Bake inputs. Module lintFix and focused Gradle/uv/Ruff checks passed; no application tests were
added or modified. New images were not substituted into the running environment.

Temporary probes, copied dependency/artifact fixtures and benchmark image tags were removed.
Persistent service data and shared caches were retained; the last environment status reported GMS
and frontend healthy. The tables in this report retain the reproducible commands and summarized
results. Raw profiler recordings and temporary logs were measurement-time artifacts and are
intentionally not referenced as durable evidence because they are unavailable outside the machine
that produced them.

## Review follow-up validation

Review fixes were validated on the same host and warm workspace on 2026-09-16. The commands used the
repository's mise toolchain, Gradle daemon and existing dependency caches.

| Path                         | Before review fixes       | After review fixes         | Result                                                                   |
| ---------------------------- | ------------------------- | -------------------------- | ------------------------------------------------------------------------ |
| Warm `yarnInstall`           | 3.46, 3.29, 3.21 s        | 3.46, 3.05, 3.02 s         | Median 3.29 s to 3.05 s; no regression                                   |
| Warm frontend context        | 5.89 s                    | 3.80 s                     | Single paired observation; no regression                                 |
| Host environment translation | 44.676 microseconds/call  | 41.492 microseconds/call   | 100,000-call microbenchmark; no regression                               |
| Five no-match hook starts    | 0.20 s                    | 0.16 s                     | Process-start benchmark; no regression                                   |
| Narrowed Docker cache hit    | Not separately remeasured | 5.39 s                     | Frontend-only debug image task remained `UP-TO-DATE`                     |
| Changed prepared artifact    | Incorrectly cacheable     | 30.55 s validation rebuild | Removing a staged file reran `stage`, `dockerPrepare` and the image task |

The Yarn guard repaired a deliberately removed package descriptor before recreating its 4,190-entry
package manifest. Docker cache validation used a 42.27 s primer build; the changed-artifact rebuild
reused every image layer after transferring the context. Focused Python coverage completed 24 tests
in 0.42 s. Compose configuration for worktree slot 1 advertised Kafka at `localhost:10092`, and the
Play dry-run graph included `:metadata-service:restli-api:mainRestClientJar`.

### Surgical review corrections

The next review removed the additional `rebuild_gradle_modules` extension field and the custom
Yarn package inventory. Rebuilds derive image modules from the existing task/service mapping and
narrow only when every changed path has one service-specific owner. Shared GraphQL, metadata-io,
other shared backend modules, mixed mapped/unmapped changes and a clean worktree retain the full
graph. The earlier narrowed-build timings therefore apply only to service-owned edits.

Yarn initially checked every path recorded in `.yarn-integrity`, without hashing file contents.
That extra guard was subsequently removed: the final task tracks `package.json` and `yarn.lock`
as inputs and `.yarn-integrity` as its output marker. Partial-install repair is left to Yarn.
Docker initially compared all tag identities against existing Bake metadata in one inspection call,
including matrix variants; that entire guard was subsequently removed. Ordinary `bootRun` uses the production runtime classpath and packaged resources;
DevTools and source resources remain specific to `hostDev`. No new user settings were added.

| Measurement                           | Before these corrections             | After                             | Boundary                                                                        |
| ------------------------------------- | ------------------------------------ | --------------------------------- | ------------------------------------------------------------------------------- |
| Warm `:datahub-web-react:yarnInstall` | 3.27 s                               | 3.89, 3.72, 3.82 s; median 3.82 s | One before observation; approximately 0.55 s additional integrity checking      |
| Actual warm Yarn installation         | 11.96 s                              | 9.15 s                            | One pair forcing only `yarnInstall` out of date; Yarn itself took 5.35 / 5.29 s |
| Docker image-cache predicate          | 65.86, 74.32, 69.80 ms               | 45.58, 48.85, 49.08 ms            | Three alternating pairs after primers; two tags, inspection only                |
| Matched parent/child Spotless wrapper | Earlier post-batching median: 3.21 s | 3.38 s                            | Current single observation; both module tasks selected in one Gradle invocation |

The existing 24 focused Python tests and scoped Gradle/Ruff checks passed. Command probes verified
seven automatic rebuild selections and all four explicit aliases. The now-removed Yarn guard was
validated by temporarily moving `vite/bin/vite.js` while retaining its `package.json`, then restoring
it. Docker rejected mismatched image metadata and accepted a matching matrix target.
All temporarily moved files and generated metadata were restored; no test files were added or changed.
`ty` reported four existing errors in unchanged loader/setup code, down from six errors at the
committed baseline, plus the same two deprecation warnings. It found no new type errors.

The host GMS classpath fingerprint, JVM arguments and host settings matched their pre-change values;
ordinary `bootRun` excluded DevTools. These are configuration checks, not new startup/reload timings.
After removing the Yarn file scan, warm task samples were 3.23, 3.07 and 3.04 s (median 3.07 s), all
up to date. A 13.46 s invocation starting a new daemon was excluded as a primer. These are subsequent
observations, not an alternating comparison. The measurements do not establish zero regressions
across every workflow; shared edits intentionally run the full graph for correctness.

### Native Docker cache follow-up

The preparation-enabled comparison initially failed in `:datahub-actions:dockerPrepare`, before
Docker ran. Its up-to-date predicate tried to resolve cross-project task dependencies after Gradle
had finalized configuration. The minimal reproduction was
`mise exec -- ./gradlew :datahub-actions:dockerPrepare --offline --console=plain`.
Disabling parallel execution did not fix it. Reading dependencies from the already-populated
execution graph (`gradle.taskGraph.getDependencies(task)`) fixed the failure without changing
Gradle settings. The original command then passed in approximately 4 s; excluding code generation
also passed in approximately 3 s. Full preparation subsequently completed all 271 tasks, with
173 executed and 98 up to date; its 137 s included rebuilding stale artifacts and is not a warm
performance sample.

Debug Bake now honors the existing frontend `contextDirectory` and depends on the existing
`prepareDockerContext` Sync task. Other modules still use their existing root contexts. This adds
no user setting or second context implementation.

| Comparison                 | Full worktree context    | Existing staged context | Boundary                                                                           |
| -------------------------- | ------------------------ | ----------------------- | ---------------------------------------------------------------------------------- |
| Frontend native image task | 25.862, 25.904, 26.397 s | 7.030, 4.992, 5.283 s   | Three warm samples per context; image-only Gradle invocation, preparation excluded |
| Median                     | 25.904 s                 | 5.283 s                 | All eight image steps cached in every counted sample                               |

The context experiment also checked that the inspected filesystem layers and runtime configuration
matched. Image metadata digests were not stable, so digest equality was not used as that assertion.

The subsequent whole-stack runs used
`mise exec -- ./gradlew :docker:buildImagesquickstartDebug --offline --console=plain`.
A temporary init script redirected tags to isolated benchmark images for both modes. For native
mode only, it forced the image task's up-to-date predicate false. No preparation tasks were excluded
or forced to rerun. Source diffs and generated Bake definitions had identical hashes across the
unchanged runs. The environment used Docker 28.4.0, Buildx 0.13.1 and BuildKit 0.24.0 on ARM64.

| Whole-stack scenario                          | Native Docker invocation | Existing guard         | Interpretation                                                                                                   |
| --------------------------------------------- | ------------------------ | ---------------------- | ---------------------------------------------------------------------------------------------------------------- |
| First unchanged run after image primer        | 188.602 s                | 8.700 s                | Actions base/dependency installation unexpectedly reran                                                          |
| Subsequent unchanged runs                     | 35.723, 34.939 s         | 8.074, 8.149, 7.608 s  | Native runs still reran Actions dependency installation; guarded image task was up to date                       |
| Fresh frontend configuration edit             | 67.875 s                 | 30.561 s               | Both rebuilt preparation and image outputs; different cache misses prevent treating this as a speedup comparison |
| Repeat after guarded edit                     | Not measured             | 7.474 s                | Image task returned to up to date                                                                                |
| Restore original frontend source, then repeat | Not measured             | 36.222 s, then 9.058 s | Restoration rebuilt successfully; repeat skipped the image task                                                  |

The edit probes used different temporary comments in `mfe.config.dev.yaml`. Both reran resource
processing, staging, context Sync, `dockerPrepare` and image construction. Reading the guarded
image archive, without starting a container, confirmed the changed comment was actually packaged.
The source and generated context were restored afterward. These are build-phase measurements,
not application-readiness timings or evidence for every kind of source change.

Cache-record snapshots showed the approximately 444 MB Actions dependency-install record and its
downstream records disappearing between identical builds, with a replacement created under the
same parent. The base-image digest remained unchanged. This establishes cache churn on this builder,
but does not establish why the records disappear; garbage collection or a builder-specific issue
remains unproven. No daemon settings, builder versions or shared caches were changed to mask it.

These observations initially led to retaining the guard. That decision was reversed: the guard,
Git fingerprinting, metadata/tag comparison and synthetic preparation markers are now removed.
Plain Gradle lifecycle tasks already propagate dependency up-to-date state, so the marker and its
one-line graph-lookup fix are both unnecessary. No replacement cache or user setting was added.

#### Guard-free validation and Docker GC diagnosis

The same full preparation/image task now invokes Bake unconditionally. Temporary instrumentation
recorded BuildKit's per-step cache status and Gradle lifecycle state; no instrumentation is in the
repository. The first invocation after changing Gradle scripts took 26.920 s and is excluded from
the warm samples below. Docker reused all 29 `RUN` steps even in that primer.

| Guard-free scenario               | Total time                       | Verification                                                                      |
| --------------------------------- | -------------------------------- | --------------------------------------------------------------------------------- |
| Four unchanged full builds        | 13.146, 12.028, 11.257, 11.509 s | All 29 `RUN` steps cached in every run                                            |
| Fresh frontend configuration edit | 39.953 s                         | Only affected frontend layers rebuilt; all dependency-install steps cached        |
| Repeat after edit                 | 12.086 s                         | All 29 `RUN` steps cached                                                         |
| Restore source, then repeat       | 19.318 s, then 11.387 s          | Native cache reused the original layers; final preparation returned to up to date |

The edited file was verified inside the image archive without starting a container. During the
edit, only the frontend `dockerPrepare` lifecycle task reported `upToDate=false`; unchanged modules
reported true. Thus removing the marker preserves the existing reload-selection signal. The source
and generated context were restored. The warm native path costs approximately 3–5 s more than the
earlier approximately 8 s guard shortcut; it is not a zero-regression claim. These are build-phase
observations, not new startup or cold-cache measurements.

Direct Bake runs, the full multi-image graph, metadata output, and a base-stage/final-stage tag
round-trip all retained dependency-layer hits in this series. The earlier large misses did not
recur, but a concrete host-side problem was found: the Docker 28.4.0 default GC percentage helper
divides disk capacity by the percentage instead of multiplying by percentage/100.
See the [versioned Docker GC implementation](https://github.com/moby/moby/blob/v28.4.0/builder/builder-next/worker/gc.go#L73-L76).

The host's old Buildx 0.13.1 output hid the newer policy fields. The VM's existing Buildx 0.27.0
reported the actual policy using `colima ssh -- docker buildx inspect`:

| Native GC field    | Active value |
| ------------------ | ------------ |
| Reserved space     | 9.313 GiB    |
| Maximum used space | 1.863 GiB    |
| Minimum free space | 4.657 GiB    |

Those values agree with the erroneous calculation. They make native GC a plausible contributor to
the earlier cache loss, but do not prove causality or rule out repository-driven invalidation.
At this stage no daemon policy, tool version, shared cache or normal debug image had been changed.
Temporary benchmark images were removed; no tests were added or modified.

#### Docker update and retry

The subsequent [Colima runtime update](https://colima.run/docs/runtimes/#updating-runtimes)
upgraded Docker **28.4.0 → 29.8.1** and embedded BuildKit **0.24.0 → 0.33.0** in place.
The daemon configuration and host Docker client/Buildx were unchanged. Native GC then reported
69.85 GiB maximum used space and 17.7 GiB minimum free space, with the same 9.313 GiB reservation.
No custom cache policy or repository workaround was added.

The same guard-free `:docker:buildImagesquickstartDebug` task, including preparation, was measured
with isolated image tags before and after the update:

| Scenario                               | Docker 28.4.0                    | Docker 29.8.1            | Cache verification                                                     |
| -------------------------------------- | -------------------------------- | ------------------------ | ---------------------------------------------------------------------- |
| Immediate pre/post-update warm repeats | 12.949, 11.005 s                 | 11.836, 11.126, 11.480 s | All 29 `RUN` steps cached                                              |
| Fresh frontend configuration edit      | 39.953 s (earlier run)           | 37.436 s                 | Only affected frontend layers rebuilt; dependency-install steps cached |
| Repeat after edit                      | 12.086 s (earlier run)           | 10.901 s                 | All 29 `RUN` steps cached                                              |
| Restore source, then repeat            | 19.318 / 11.387 s (earlier runs) | 18.662 / 10.734 s        | All 29 `RUN` steps cached; final preparation up to date                |

The first pre-update invocation took 38.808 s with all 29 `RUN` steps cached; the first after updating
took 22.318 s with 28 cached and only the frontend's final `RUN echo 9002` rerun. These are reported
separately from the warm repeats. The source-edit timings are single observations, not a controlled
speedup estimate. Image-archive inspection confirmed the fresh edit was included without starting
a container. The source was restored, and existing containers, volumes and normal debug image IDs
were preserved. Only rebuildable benchmark tags were removed; no cache prune was performed.

Native caching passed these checks without the guard, and no large dependency-layer miss recurred.
The update corrected the observed default GC limits, but warm builds were already fast immediately
before it. This short series therefore does not prove the update caused the earlier intermittent
stalls to disappear or exclude every repository invalidation issue. These remain build-phase
measurements, not startup/readiness or cold-cache results.
