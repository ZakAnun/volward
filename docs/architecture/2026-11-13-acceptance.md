# Structural refactor acceptance — 2026-11-13

Plan baseline: `fd89c111b35bc498f29dbab4573801aded8cc6de`. Task 10 begins at `804b6ef`. Host: Darwin arm64; Rust/Cargo 1.97.0, Flutter stable 3.47.4 (Dart 3.13.3), Node 24.22.1, pnpm 10.13.1. This record covers local verification, with no deployment, publishing, purchase or signing.

**Result: accepted with concerns, not an unconditional whole-product acceptance.** Dart analysis/format/full tests, Rust tests/builds, Platform API, website type/tests/build and the arm64 FFI matrix pass. Native packaging remains unaccepted. The AI owner/handoff adaptations have focused/full tests but remain unaccepted as identical across original concurrency races; see [source review D7/D8/D11](source-review.md). The [architecture table](../../ARCHITECTURE.md) gives per-module entries, dependency rules, state owners and results.

## Validation commands and outcomes

Commands ran through `rtk` (`rtk proxy` where needed); logs are retained in `/private/tmp/volward-task10`. The existing independent baseline source/build is `/private/tmp/volward-baseline-fd89c11`.

| Command / log | Outcome |
|---|---|
| `bash scripts/test_check_architecture.sh && bash scripts/check_architecture.sh` | Passed. Negative fixtures reject feature→FFI, shared→feature and server→engine edges; the current repository has no mechanically prohibited edge. |
| `bash scripts/ensure_fvm_stable.sh` / `/private/tmp/volward-task10-fvm.log` | Passed; stable retained. No version pin or tracked FVM change. |
| `bash scripts/check_dart_format.sh` / `dart-format.log` | Installed SDK cache writes denied by sandbox; not a formatting result. |
| Staged stable `dart format --output=none --set-exit-if-changed .` in app / `dart-format-staged.log` | Passed: 247 files, 0 changed. Baseline Task 0 had 39 format differences; earlier plan formatting plus the same staged stable now yields zero. |
| Staged stable `flutter analyze --no-pub` / `flutter-analyze.log` | Passed, no issues. |
| Staged stable `flutter test --no-pub` / `flutter-test.log` | Initial sandbox run: all 98 suites failed loading because localhost socket binding was denied; no assertions ran. |
| Same Flutter command with auto-approved sandbox escalation / `flutter-test-unrestricted.log` | Passed: **955 tests**, exit 0. This is the full app suite. |
| `cargo test --workspace -- --test-threads=1` / `rust-workspace-final.log` | Passed: **351 passed, 2 ignored, 19 suites** after final server boundary change. Serial execution avoids pre-existing test races over `VOLWARD_CACHE_DIR`; baseline serial result was 345 passed, 2 ignored. |
| `cargo test -p volward-platform-api` / `platform-tests.log` | Passed: **65 tests**, 4 suites. Final workspace rerun includes the same tests after DTO relocation. |
| `cargo run -p volward-cli -- scan-bench --entries 10 --iterations 1` / `cli-bench.log` | Passed, bounded synthetic benchmark (10 entries). |
| `cargo build -p volward-facade` / `facade-build.log` | Passed on macOS arm64; debug artifact used below. |
| `cargo build --release -p volward-facade` / `facade-release-build.log` | Passed on macOS arm64; no signing. |
| `SITE_URL=http://localhost:4321 PADDLE_CLIENT_TOKEN=test_placeholder PADDLE_ENV=sandbox bash scripts/website_build.sh` / `website-build.log` | Passed: 3 routes. Local placeholder only; GitHub release fetch unavailable, existing fallback used. |
| `pnpm test --run` in website / `website-tests.log` | Passed: **81 tests, 11 files** after configured build. |
| `SITE_URL=http://localhost:4321 bash scripts/check-website.sh` | Passed generated en/zh HTML/canonical/metadata checks. |
| `pnpm check` / `website-check.log` | Configuration error without SITE_URL; retried below. |
| `SITE_URL=http://localhost:4321 ./node_modules/.bin/astro check` | Passed: **0 errors, 0 warnings, 0 hints** after narrowing the optional ResizeObserver target, typing the test fixture as a string record, and removing two unused bindings. |
| `./node_modules/.bin/vitest run` | Passed: **81 tests, 11 files** after the type-only cleanup. |
| Standalone candidate-cache smoke | Passed: owner-scoped entries isolate the same snapshot across engines, owner entries reuse correctly, and snapshot-wide clear keeps legacy compatibility. |
| Staged stable `flutter build macos --debug --config-only --no-pub` / `macos-config.log` | **Blocked** resolving SwiftPM: sandbox denies Xcode DerivedData, clang ModuleCache and SwiftPM diagnostic/cache writes. No app build or signing occurred; tracked Xcode files unchanged. |
| `bash -n` on release/macOS/Linux/platform API/website shell builders | Passed shell syntax only, not platform packaging. |
| `git diff --check fd89c11` plus staged new files / final self-review | Passed. New docs/DTOs explicitly staged and checked; tracked FVM, all Cargo manifests, Cargo.lock, proto/rules/migrations, workflows and packaging scripts have empty baseline diff. |

Staged SDK: `/private/tmp/volward-architecture-flutter-stable`; Flutter commands use `XDG_CONFIG_HOME=/private/tmp/volward-architecture-flutter-config`. The original installed SDK was tried first. The staged SDK reports stable revision `9584c6713b324636289d067944a46fd6b49df14b`; tracked `.fvmrc`/FVM JSON remain `stable`.

## Dependency and source evidence

[Dart edges](dart-dependencies.tsv): 151 files, 513 explicit local import/export/part edges, zero unresolved local paths. A Python scan resolves relative and `package:volward/` URIs; Session parts are collapsed into their owner library before Tarjan SCC analysis. The six SCC memberships exactly match the independent baseline's 122 files/443 edges. Imports of external packages are outside this local graph; this is not a dynamic dependency analysis. All six residual SCCs and permitted infrastructure adapters are named in ARCHITECTURE.md.

[Cargo edges](cargo-dependencies.tsv): generated from `cargo metadata --no-deps --offline --format-version 1`, 7 workspace crates, 10 direct internal edges, no cycle, exactly equal to baseline. Server's sole Volward dependency is `volward-ai`; it has no desktop/core/facade edge. Compiler/privacy checks and source import inspection verify the private engine/C ABI modules are not externally accessed. Browse/scan/delete standalone libraries have no direct FFI import; their three implementation parts intentionally belong to Session. Only native_bridge imports the binding families. AI worker/native/session adapters are declared infrastructure access points.

The service-to-handler DTO dependency found during this audit was removed: `ai/types.rs` now holds shared DTOs and unchanged validation, `handlers` preserves public re-exports, `application` imports types. Billing ledger is private; all intended calls compile through its root or old proxy re-exports. Existing auth↔billing capability coupling remains (authorization one way, balance selection the other), through declared root entries.

The [source review](source-review.md) inventories every non-identical Dart function group, explains source/call-site changes and notes the concurrency limit. Rust C API's 71 exported signatures and bodies are byte-identical. The Task 10 Engine comparison was whitespace-equivalent; the later fix wave narrows same-file helper visibility. All 134 original Dart FFI typedefs match; [ABI signatures](abi-signatures.tsv) retain the baseline locations explicitly labelled as such. No protocol/schema/rule/persistence format or external route changed.

## Native artifact matrix

Both libraries are Mach-O arm64, each with exactly the same 71 `_volward_*` exports (`nm -gUj`, filtered and sorted). C signatures are compared independently from source; symbol equality alone is not used as a signature proof.

| Artifact | Verified source / loaded path | SHA-256 |
|---|---|---|
| Baseline fd89c11 | `/private/tmp/volward-baseline-fd89c11/libvolward_facade.dylib`; loaded copy `/private/tmp/volward-task10/baseline/Frameworks/libvolward_facade.dylib` | `cf08184dc7b64d2b92acdce7026f92a38d63e143de688f69c0c18253f50ab759` |
| Current debug | `<repo>/target/debug/libvolward_facade.dylib`; loaded copy `/private/tmp/volward-task10/current/Frameworks/libvolward_facade.dylib` | `1a26e6ea968ca2a78c8e278e6d61ac1bb2a900feca6cee475242889b1ebcf031` |

The current Dart harness imports the production `VolwardNativeBridge`, compiles with the Flutter frontend server, and runs under isolated copied `flutter_tester` binaries in each `MacOS/` directory. It uses the unmodified production executable-relative loader, so each process opens its own sibling Frameworks library. ICU data is supplied explicitly. Each run has a separate `VOLWARD_CACHE_DIR`, and source/copy hashes match. This is headless Flutter-engine execution, not a packaged desktop GUI.

| Current Dart against | Scan + root/subdir query | Size/name query parity + refresh | New engine + fresh-process restore | Legacy baseline JSON restore |
|---|---|---|---|---|
| Baseline library | Pass | Pass | Pass, saved `.pb` | Pass |
| Current library | Pass | Pass | Pass, saved `.pb` | Pass |

Fixed fixture: `/private/tmp/volward-baseline-fd89c11/scan-fixture` (one root file and two subdirectory files). The size and name queries are compared between libraries; this fixture does not prove that those sort modes produce different orders. Async scan completes with bounded polling; queries verify two root/two subdir children, refresh equals query, saved manifest identifies PB path, recreated engine matches the prior result. A second process restores the same PB without scanning and returns exactly the prior output. Across baseline/current results, only random snapshot ID and harness/library/cache paths are excluded from comparison; all remaining fields match. AI batch size remains 40. Logs: `smoke-{baseline,current}.log`, `restart-{baseline,current}.log`, `smoke-compile.log`; script/dill and symbol lists remain in the evidence directory. An initial harness launch lacked ICU data and aborted before Dart; corrected invocations above pass.

No actual trash operation, huge catalog, permission-protected scan or real AI network call is claimed by this small fixture. Both libraries contain optional symbols, so missing-symbol fallbacks are source-preserved but not covered by this matrix. The synchronous and asynchronous scan-start wrappers now free their returned Rust strings after decoding; C signatures and allocation ownership remain unchanged.

## Packaging and platform gaps

| Target | What was verified | Unaccepted / unavailable coverage |
|---|---|---|
| macOS arm64 | Rust debug/release builds; current Dart/native matrix; Flutter compile/tests; release script syntax and asset matcher tests | Config-only dependency setup blocked as above. No current `.app`, zip, native GUI scan/restore or package checksum. The repository macOS Rust copy script unconditionally ad-hoc signs the copied dylib; full packaging was not invoked under the no-sign constraint. |
| macOS x64 | Workflow/website agree on `volward-v<version>-macos-x64.zip` | No x64 build, runtime, ABI binary or package. |
| Windows x64 | Workflow/website installer matcher for `VolwardSetup-v<version>-windows-x64.exe` | No Windows runner/toolchain, DLL runtime, Inno Setup installer or update execution. |
| Linux x86_64 | Shell syntax and website matcher for `Volward-v<version>-linux-x86_64.AppImage` (workflow also has portable tar) | No Linux GTK build/runtime, appimagetool packaging or update execution on this macOS host. |
| Platform deployment / website publish | Local service tests, static website build and checkout/release contract tests | No deployment, live payment/AI, strict live-release verification, signing or publishing. |

Release asset names, checksum exclusion and `_ptxn` checkout behavior are covered by website/server tests and unchanged workflows; they do not establish that native installers were produced.

## Task 10 self-review and disposition

Task 10 production changes are limited to a corrected Engine cache comment, private ledger visibility and an unchanged DTO/validator relocation removing the service→HTTP dependency. Three new server tests verify synthesis debit/refund ordering and both endpoints' refund-failure error preservation. DTO text compared byte-for-byte with `804b6ef`, except validator visibility. Workspace tests were repeated after this final structural change. All prior scan/deletion/AI behavior changes are inventoried in the source review instead of hidden as formatting.

Architecture, README link, acceptance evidence and source review are tracked deliberately even though `docs/` is ignored for local drafts; only the named architecture files are force-added. Temporary logs/binaries and the agent task report remain local. No broad ignore rule, FVM policy, remote state or user data was changed. Outstanding concerns are native packaging/platform gaps, residual Dart cycles and strict concurrency-equivalence limits of the AI owner changes.
