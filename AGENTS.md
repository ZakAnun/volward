# Agent instructions (Volward)

## Flutter / FVM

- Project Flutter SDK is **`stable`** via FVM (`apps/volward/.fvmrc`).
- **Do not** run `fvm use <version>` with a specific release (e.g. `3.44.7`). That rewrites tracked config files.
- Before Flutter tests or format checks, run:
  - `bash scripts/ensure_fvm_stable.sh`, or
  - `bash scripts/test_core.sh flutter` / `bash scripts/check_dart_format.sh` (they call ensure internally).
- If FVM is missing, scripts fall back to `flutter` / `dart` on `PATH`.

## Commits

- Never commit changes to `apps/volward/.fvmrc` or `apps/volward/.fvm/fvm_config.json` unless explicitly changing the team's Flutter policy (should stay `stable`).
