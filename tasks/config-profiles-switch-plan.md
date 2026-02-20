# Config Profiles Switch Plan

## Goal
Move from single flat config to multi-profile config in one file, with explicit default profile selection and optional override of active profile.

## Deliverables
1. Profile-capable config loader.
2. Backward compatibility for existing flat config.
3. README update with new schema and examples.
4. Tests for profile selection, env override, and legacy compatibility.

## Implementation Tasks

### 1) Data model changes (`Sources/TranscribeMini/AppConfig.swift`)
1. Keep existing `AppConfig` as resolved runtime config.
2. Add new file-decoding types:
   - `ProfilesFileConfig` with `defaultProfile` and `profiles`.
   - `ProfileConfig` (per-profile optional fields; similar to current `FileConfig`).
3. Support legacy flat format by decoding either:
   - legacy `FileConfig`, or
   - new `ProfilesFileConfig`.

### 2) Active profile resolution
1. Add env override key: `TRANSCRIBE_PROFILE`.
2. Selection priority:
   1. `TRANSCRIBE_PROFILE` (if set)
   2. file `defaultProfile`
   3. deterministic fallback:
      - first profile key (sorted), or
      - legacy/default behavior when no profiles exist
3. If selected profile is missing:
   - log warning
   - fallback to deterministic profile/defaults (do not crash).

### 3) Merge behavior
1. Build effective config in this order:
   1. in-code defaults
   2. selected profile fields from file
   3. environment variable overrides (same keys as today)
2. Keep all current env keys working (`TRANSCRIBE_PROVIDER`, `TRANSCRIBE_MODEL`, etc.).
3. Apply env values to the selected profile result only.

### 4) Diagnostics
1. Add resolved profile name to startup log in `Sources/TranscribeMini/AppDelegate.swift`.
2. Do not log sensitive values (API key).

### 5) README updates (`README.md`)
1. Replace flat-only examples with profile-based primary example.
2. Add section:
   - `defaultProfile`
   - `TRANSCRIBE_PROFILE` override usage
3. Keep legacy flat config documented as deprecated but supported.

### 6) Tests (`Tests/TranscribeMiniTests/AppConfigTests.swift`)
1. Add tests for:
   - selecting `defaultProfile`
   - selecting profile via `TRANSCRIBE_PROFILE`
   - env override applied after profile selection
   - invalid profile name fallback
   - legacy flat config still loading
2. Keep existing tests where still valid; update expectations where loader behavior changes.

## Acceptance Criteria
1. One config file can define at least these profiles:
   - OpenAI online
   - Apple local
   - whisper.cpp model A
   - whisper.cpp model B
2. `defaultProfile` determines active profile at startup when no override exists.
3. `TRANSCRIBE_PROFILE=...` switches active profile without editing JSON.
4. Existing flat configs continue to work.
5. README clearly documents migration and usage.

## Proposed Migration Strategy
1. Ship loader with dual-format support (legacy + profiles).
2. Update README examples to profile format.
3. Later cleanup release can remove legacy format only after migration window.

## Known Baseline Issue (Unrelated)
- `swift test` currently fails due to missing `TranscriptSanitizer` symbol in `Tests/TranscribeMiniTests/TranscriptSanitizerTests.swift`.
- This should be fixed or scoped separately so profile-change tests can be validated cleanly.

## Clarifications Needed Before Implementation
1. Should `TRANSCRIBE_PROFILE` be temporary runtime-only, or should app ever persist chosen profile back into config?
2. Do you want profile names to be arbitrary strings, or a fixed set (`openai`, `apple`, `whisper-base`, etc.)?
3. For missing profile override, should app fallback with warning (recommended) or fail fast?
4. Should provider-specific env vars (like `OPENAI_API_KEY`, `GROQ_API_KEY`) still auto-apply regardless of selected profile?
5. Do you want a future menu action to switch profiles from the menubar, or config/env-only for now?
