# Repository Guidelines

## Project Structure & Module Organization
This is a Swift Package Manager executable for macOS.
- `Sources/TranscribeMini/`: app entrypoint and core modules (`AppDelegate`, hotkey handling, recording, transcription, text injection, config).
- `Tests/TranscribeMiniTests/`: `XCTest` unit tests for config parsing, transcriber factory behavior, and multipart request building.
- `Package.swift`: package definition and target wiring.
- `README.md`: runtime setup, permissions, and provider configuration.

Keep new production files under `Sources/TranscribeMini/` and mirror test coverage in `Tests/TranscribeMiniTests/`.

## Build, Test, and Development Commands
Use SwiftPM from repo root:
- `swift build`: compile the app in debug mode.
- `swift run`: run the menubar app locally.
- `swift test`: run the full test suite.

Useful local run with hosted transcription:
- `export OPENAI_API_KEY=... && export TRANSCRIBE_PROVIDER=openai && swift run`

## Coding Style & Naming Conventions
- Follow existing Swift style: 4-space indentation, one type per responsibility, and clear small methods.
- Use Swift naming conventions: `UpperCamelCase` for types, `lowerCamelCase` for functions/properties, descriptive enum cases (for example `.whispercpp`).
- Prefer immutable values (`let`) unless mutation is required.
- Keep files focused; split large features into dedicated types in `Sources/TranscribeMini/`.
- No formatter/linter is configured in this repo; keep style consistent with surrounding code and Swift API Design Guidelines.

## Testing Guidelines
- Framework: `XCTest`.
- Name tests as `test<Behavior>()` (for example `testFactoryCreatesAppleTranscriber`).
- Add/adjust tests for any behavior change, especially provider selection, config precedence, and transcription request construction.
- Run `swift test` before opening a PR.

## Commit & Pull Request Guidelines
Current history uses concise, imperative commit subjects (for example `Build minimal hold-to-talk macOS transcriber...`).
- Commits: one logical change per commit, imperative subject line, no trailing period.
- PRs should include: what changed, why, how it was tested (`swift test` output summary), and any macOS permission/setup impacts.
- Link related issues/tasks and include screenshots or short recordings when UI/menubar behavior changes.

## Security & Configuration Tips
- Never commit API keys or personal config files.
- Use environment variables (`OPENAI_API_KEY`, `GROQ_API_KEY`, `TRANSCRIBE_*`) or `~/.transcribe-mini.json` for local secrets.
- Validate permission-dependent flows (Microphone, Accessibility, Speech Recognition) when changing recorder or paste behavior.
