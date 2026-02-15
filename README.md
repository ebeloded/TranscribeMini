# TranscribeMini

A minimal macOS hold-to-talk transcription app.

Interaction:
- Hold `Option + Shift + D`: recording starts immediately.
- Release `Option + Shift + D`: recording stops, audio is transcribed, text is pasted at your cursor.

## Run

```bash
swift run
```

If you already have an OpenAI key in your shell env:

```bash
export OPENAI_API_KEY="YOUR_OPENAI_API_KEY"
export TRANSCRIBE_PROVIDER="openai"
swift run
```

## Permissions (required)

On first run, macOS will ask for:
- Microphone access (for recording)
- Accessibility access (for global hotkey + synthetic Cmd+V paste)
- Speech Recognition access (when `provider` is `apple`)

Grant access in:
- `System Settings > Privacy & Security > Microphone`
- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Speech Recognition`

Important when using `swift run`:
- macOS may attach Accessibility permission to your terminal app (`Terminal`, `iTerm`, etc.) instead of `TranscribeMini`.
- If `TranscribeMini` does not appear in Accessibility, enable your terminal app there.
- You can also add the built binary directly from:
  - `/Users/ebeloded/Projects/transcribe/.build/debug/TranscribeMini`

## Config

Config is loaded in this order:
1. Defaults
2. `~/.transcribe-mini.json` (optional)
3. Environment variables (override file/defaults)

Supported environment variables:
- `TRANSCRIBE_PROVIDER` (`apple`, `openai`, `groq`, `whispercpp`)
- `TRANSCRIBE_API_KEY` (or `OPENAI_API_KEY` / `GROQ_API_KEY`)
- `TRANSCRIBE_MODEL`
- `TRANSCRIBE_ENDPOINT`
- `TRANSCRIBE_LANGUAGE`
- `TRANSCRIBE_LOCAL_MODEL` (path to local whisper.cpp model; overrides `TRANSCRIBE_MODEL`)
- `WHISPER_CLI_PATH` (default: `/opt/homebrew/bin/whisper-cli`)
- `WHISPER_STREAM_PATH` (default: `/opt/homebrew/bin/whisper-stream`)
- `TRANSCRIBE_STREAMING` (`true`/`false`, default: `true`)

Optional file: `~/.transcribe-mini.json`.

### Local Apple Speech (default)

```json
{
  "provider": "apple",
  "apiKey": "",
  "model": "gpt-4o-mini-transcribe",
  "language": "en-US"
}
```

### OpenAI hosted transcription

```json
{
  "provider": "openai",
  "apiKey": "YOUR_OPENAI_API_KEY",
  "model": "gpt-4o-mini-transcribe",
  "language": "en"
}
```

### Groq OpenAI-compatible endpoint

```json
{
  "provider": "groq",
  "apiKey": "YOUR_GROQ_API_KEY",
  "model": "whisper-large-v3",
  "language": "en"
}
```

### Local whisper.cpp (on-device)

```bash
brew install whisper-cpp
mkdir -p "$HOME/.transcribe-mini/models"
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin \
  -o "$HOME/.transcribe-mini/models/ggml-tiny.en.bin"

export TRANSCRIBE_PROVIDER="whispercpp"
export TRANSCRIBE_LOCAL_MODEL="$HOME/.transcribe-mini/models/ggml-tiny.en.bin"
export TRANSCRIBE_LANGUAGE="en"
export TRANSCRIBE_STREAMING="true"
swift run
```

Streaming behavior in `whispercpp` mode:
- Hold `Option + Shift + D`: starts `whisper-stream` immediately.
- Release `Option + Shift + D`: stops stream and pastes captured text.
- While holding, the latest partial text is shown as menu bar tooltip.

Quick local smoke test (without launching the app):

```bash
say "local smoke test transcription works" -o /tmp/transcribe-mini-smoke.aiff
afconvert -f WAVE -d LEI16@16000 /tmp/transcribe-mini-smoke.aiff /tmp/transcribe-mini-smoke.wav
/opt/homebrew/bin/whisper-cli \
  --model "$HOME/.transcribe-mini/models/ggml-tiny.en.bin" \
  --language en \
  --output-txt \
  --output-file /tmp/transcribe-mini-smoke \
  --no-prints \
  --file /tmp/transcribe-mini-smoke.wav
cat /tmp/transcribe-mini-smoke.txt
```

Optional override:

```json
{
  "endpoint": "https://your-endpoint.example.com/audio/transcriptions"
}
```

## Notes

- Menubar icon states:
  - `T`: idle
  - `R`: recording
  - `!`: last action failed
- Default hotkey is hardcoded to `Option + Shift + D`.
- Audio is recorded as `.wav` to support local whisper.cpp directly.
