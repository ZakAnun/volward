# Volward architecture

This describes the implemented boundaries after the November 2026 structural refactor, not a proposed directory layout. The [acceptance record](docs/architecture/2026-11-13-acceptance.md) records checks, baseline comparisons and remaining gaps. The [Dart edge list](docs/architecture/dart-dependencies.tsv), [Cargo edge list](docs/architecture/cargo-dependencies.tsv) and [source review](docs/architecture/source-review.md) provide the detailed evidence.

## Capability map and state ownership

Paths in the first table are relative to `apps/volward/lib/`.

| Capability / actual entry | Allowed dependencies | Mutable-state owner | Acceptance |
|---|---|---|---|
| Desktop composition: `main.dart`, `DirectoryDetailsPage`, `home_page.dart` | Session, capability interfaces, theme/updater/account entry points, widgets | Page State owns selected columns, selection, view mode and view caches; supplied Session owns domain state | Analyze + 955 Flutter tests pass; native GUI/packaging gap |
| Browse: `features/browse/` (`CatalogReader`, `DirectoryBrowseSession`, `SnapshotCatalog`, widgets); shared `snapshot_query.dart`, `snapshot_view_cache.dart` | Query/tree/entry models, Flutter, injected catalog reader; no direct bridge access | Catalog caches its directory lookup; page owns query/view caches; Session owns authoritative index version and overlays | Tests + both-library directory smoke pass; legacy cycle below |
| Scan: `features/scan/` (`ScanLifecycle`, `ScanPreferences`, progress/types/decoder) | Shared snapshot models and narrow contracts; implementation part belongs to Session | Session owns roots, current directory, scan/restore flags, generations, progress, worker ports and timers | Full suite + native scan/restore pass |
| Deletion: `features/deletion/` (`DeletionActions`, `deletedEntryOverlay`) | Entry/tree models; implementation part belongs to Session | Session owns deleting flag, report, refresh queues and overlays; overlay helper has no persistent state | Full suite + Rust delete tests pass; no real deletion in smoke |
| Session facade: `volward_session.dart` | Scan/browse/delete contracts and helpers, bridge, cache/settings, capability analysis, analytics | Same `VolwardSession` instance owns engine pointer and all orchestration state; delegates do not duplicate it | Full suite pass; exact same-owner lifecycle preserved by delegates |
| Capabilities: `capabilities/capability_analysis.dart`, models/result cache | Injected call/cancel functions, models/cache | Session retains native dispatch/job polling; injected cache stores results | Flutter capability tests and Rust analyzers pass |
| AI: `ai_contract_api.dart`, `SessionAiContract`, `BridgeAiContract`, `AiAnalysisGateway`, `AiCoverageJobs` | Contract/model layer; Session adapter and worker adapter own infrastructure access; providers use contracts | Coordinator owns service/provider/subscription and serial handoff; service owns worker/controller; stores own persisted job/verdict data; UI owns display state | Owner-handoff equivalence remains unaccepted; focused regression evidence is recorded separately |
| FFI: `bridge/native_bridge.dart`, `bridge/bindings/{scan,index,delete,capabilities,ai}.dart`, `bridge/scan_worker.dart` | `dart:ffi`, ffi allocator, platform loader, AI debug logging; bindings are declaration-only | Session owns main engine; isolate workers create/free separate engines; bridge owns symbol lookups | 134 original typedefs, 71 C exports unchanged; both-library smoke passes |
| Preferences: `settings/settings_file.dart`, `theme/volward_theme_settings.dart`, `ai/ai_settings_store.dart` | Shared cache path, secure storage and account/provider entries | Theme owns theme/locale/accent/update preferences; AI owns AI/provider/privacy/budget/narrative preferences; Linux integration owns desktop-entry path | Tests pass; separate read/modify/write operations are retained, not serialized together |
| Storage: `snapshot_cache.dart`, `scan_root_record.dart`, `proto/` | File I/O and wire models | Native index is authoritative; cache/root-record stores persist snapshots/manifests/root status; Session writes `session.json` | Legacy JSON/PB Rust tests and current Dart restore pass |
| Updater / analytics / localization | Existing `updater/`, `analytics/`, `l10n/` entries and platform adapters | AppUpdater owns download state; Analytics singleton owns selected implementation; theme owns locale preference | Existing Flutter suite pass; installed update and telemetry not exercised |

Rust and service entries:

| Capability / actual entry | Allowed dependencies | Mutable-state owner | Acceptance |
|---|---|---|---|
| `volward-core/src/lib.rs`: scan, classify/rules, index/query, delete, capability and Coverage APIs | Standard/external libraries; `PlatformStorage` abstraction; no other Volward crate | Orchestrator/builders own per-operation state; indexes and cache objects own their data; caller supplies cancellation | Workspace pass; core source unchanged |
| `platform-desktop` | core + OS/file traversal libraries | DesktopPlatform and traversal jobs | Workspace pass on arm64 macOS only |
| `volward-index-pb` | core + protobuf libraries | Codec/atomic writer; no new application state | Legacy format/round-trip tests pass; source/schema unchanged |
| `volward-facade::VolwardEngine` | core, desktop, index-pb, AI | Parent `engine.rs` owns Arc/Mutex/atomic state, snapshots, index, jobs, caches and thread handles | 147 function bodies unchanged ignoring whitespace; workspace pass |
| `engine/{scan,index_access,index_query,delete,capability,coverage,ai}.rs` | Parent engine state and declared crate APIs | Private sibling implementations on the same Engine, not independent owners | Query lock scopes/publication order unchanged; comment corrected |
| Private `capi/{mod,scan,index,delete,capabilities,ai}.rs` | Engine + C/string conversions | Engine Box created/freed through C API; returned Rust strings freed by `volward_free_string` | 71 declarations and bodies byte-identical to baseline |
| `volward-ai` | Protocol/request/parsing dependencies; no core/desktop dependency | Request values; no shared engine state | Workspace pass; source unchanged |
| `volward-cli` | core, index-pb, desktop | CLI invocation and benchmark data | Workspace pass; binary smoke bounded by fixtures |
| Platform `app()` / device / auth | AppState, shared DB/config/error and auth root entries; auth uses billing balance selection | SQLite owns users/devices/OTP/transactions; AppState owns pool/upstream/mailer/config | 65 Platform tests pass |
| Platform `ai/handlers.rs` → private `application.rs`, `types.rs` → `proxy.rs` and billing root | HTTP extraction/auth/validation → plain service/DTOs → upstream + ledger; no core/desktop/FFI | Request scope; AppState pool/upstream; billing owns transaction boundaries | Ordering, validation, refund and refund-failure tests pass |
| Platform `billing` root (`balance`, debit/refund) | env credit selection, DB, provider/webhook/checkout and auth entry points | Private ledger implements unchanged `BEGIN IMMEDIATE`/rollback/commit; SQLite is authoritative | Internal ledger visibility tightened; root and old proxy exports retained |
| Website `apps/website` | Astro/pages/components and local library modules; public release/checkout contracts | Browser page/client state; no server/desktop state | 81 tests + build + HTML check pass; type check passes with 0 errors, warnings and hints |

## Dependency rules

UI composition may depend on Session for assembly, but browse/scan/delete consumers use capability contracts. Pure query and model code must not import widgets or FFI implementations. The three `session_*.dart` files are deliberate `part of volward_session.dart` exceptions: they have private access to that library's state and cannot be independently imported. They are not independent feature services. Future extraction must preserve notification timing, cancellation, restore generations and state writes.

`native_bridge.dart` is the stable Dart FFI entry. Only that entry imports the five binding families; UI does not reach into them. AI contracts do not depend on FFI. The Session and worker adapters deliberately depend on their infrastructure. Session, native Coverage adapters, scan workers and the composition root are the permitted bridges to infrastructure.

`bash scripts/check_architecture.sh` enforces the mechanically checkable edges: feature/widget/shared code cannot import FFI bridge implementations, shared code cannot import feature/AI/application implementations, and the Platform API cannot depend on desktop or local engine crates. The broader graphs and the six accepted legacy SCCs remain review inputs rather than claims of complete Dart acyclicity.

Cargo's complete allowed workspace dependency set is:

```text
volward-core          -> (none)
volward-ai            -> (none)
platform-desktop      -> volward-core
volward-index-pb      -> volward-core
volward-facade        -> volward-core, platform-desktop, volward-index-pb, volward-ai
volward-cli           -> volward-core, platform-desktop, volward-index-pb
volward-platform-api  -> volward-ai
```

There are 10 internal edges and no Cargo cycle. Server code must not depend on desktop, facade, core scan/index state or their filesystem caches. Core's declared `pub mod`/`pub use` surface remains public: a caller using one of those module paths is not accessing a newly private implementation. Engine and C ABI modules remain private. Platform AI DTOs are shared below HTTP handlers; the application service does not import handlers. Auth/device/billing use root exports for cross-capability calls. Existing public auth, billing and proxy modules remain compatible; newly introduced ledger internals are private.

## Compatibility entries and persistence

- `HomePage` remains a typedef/export of `DirectoryDetailsPage`. Its callers are `main.dart` and existing widget tests; page lifecycle remains in the same State class.
- `volward_session.dart` keeps public methods and exports the scan types/progress helper. Narrow interfaces are additive; delegates use the same Session instance.
- Legacy `snapshot_catalog.dart` retains its constructor, static query API and live `VolwardSession.instance` lookup. `ScanSnapshotState.catalog` and `test/snapshot_catalog_test.dart` still use this path. Production page/browse code uses the injected `features/browse/snapshot_catalog.dart` directly.
- The original `widgets/scan_column_view.dart` and `widgets/scan_filter_bar.dart` imports remain as forwarding libraries for existing and external consumers. The latter also exports `ScanSortMode` and its label extension.
- `ai/ai_contract.dart` re-exports declarations and both adapters for external callers of the original library. No production import remains in-repo. New in-repo consumers import declarations or the appropriate adapter directly.
- `bridge/native_bridge.dart` re-exports original typedef names. Rust exports `VolwardEngine` at crate root and the same 71 `volward_*` C names. Optional-symbol fallback and loader paths remain: macOS `../Frameworks/libvolward_facade.dylib`, Linux `lib/libvolward_facade.so`, Windows sibling `volward_facade.dll`, relative to the executable.
- Platform `ai::handlers` still exports its request/response types and HTTP functions; `ai::proxy` still re-exports debit/refund. Routes, JSON fields, error bodies, JWT behavior, credit units and Paddle checkout `_ptxn` contract are unchanged.
- Cache paths, settings keys/defaults, rule YAML, protobuf schema, index versions, legacy reads and SQL migrations are unchanged. `sharedSettingsFile()` only centralizes the existing `SnapshotCache.cacheDir()/settings.json` path. BYOK credentials remain in secure storage; BYOK usage retains its separate file and lock.

## Residual couplings and limits

The import graph contains 151 Dart files and 513 local import/export/part edges. After collapsing Session parts, the same six strongly connected components exist as at `fd89c11`:

1. `scan_snapshot_state` ↔ legacy `snapshot_catalog` ↔ Session, also `scan_snapshot_merge`. This is the retained live global-reader compatibility path.
2. `ai_conclusion_synthesis`, `ai_provider`, `ai_result_groups`, `ai_result_overview` share AI result/request abstractions.
3. `coverage_client_logic` ↔ `coverage_job_state` share Coverage state conversion.
4. `ai_coverage_job_controller`, `coverage_analyze_batch`, `coverage_analyze_tree_batch` share controller/batch orchestration.
5. Analytics interface/factory ↔ Aptabase/no-op implementations.
6. Generated localization entry ↔ generated locale implementations.

No new SCC, unresolved local import, feature-to-bridge import or binding-family client was introduced. This is **not** a claim of full Dart acyclicity. Settings and AI coordinator still depend on existing infrastructure and globals at compatibility/composition seams. AI service factories still mention concrete Session; Session parts still share private state; settings owners can still race on read/modify/write of the common file. These are real constraints, not completed clean-architecture migrations.

Default production composition still uses `AiCoverageCoordinator.instance`. Separately constructed pages can own a coordinator tied to their supplied Session. The owner/handoff work adds generations, draining and stale-result guards, and scopes native in-flight plan deduplication to engine address. These are necessary ownership adaptations, not mere file moves. Candidate materialization entries produced by Session are keyed by engine address plus snapshot ID, while the legacy snapshot-only API remains available for callers that omit an owner. Their function-level review and tests are recorded in the acceptance notes; unrestricted behavioral equivalence across all races is not established by this structural audit.

Session disposal now defers engine release for Coverage plan calls, Coverage native futures and service retirement. This is not a full lifetime audit: legacy candidate polling, scan/restore, capability and other Session-native borrowers were not comprehensively traced or migrated to this guard. The isolate backfill path is guarded by the same future lease but has not been exercised by the controlled-bridge disposal test.

Both synchronous and asynchronous `startScan` wrappers now release their returned Rust strings through `volward_free_string` after decoding. Runtime smoke is functional coverage; the ownership path is also reviewed at source level.

Current verification covers macOS arm64 headless Dart/native behavior. GUI interaction, signed/notarized packages, macOS x64, Windows and Linux execution, real purchases/upstream AI and missing-optional-symbol libraries remain outside the completed matrix. See the acceptance record for exact blockers and artifact hashes.
