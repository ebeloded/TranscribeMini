# TranscribeMini

A minimal macOS hold-to-talk transcription app.

Interaction:
- Hold `Fn`: recording starts immediately.
- Release `Fn`: recording stops, audio is transcribed, text is pasted at your cursor.
- Cue sounds: start cue plays on `Fn` press; stop cue plays when recording ends.

## Run

```bash
swift run
```

If you already have an OpenAI key in your shell env:

```bash
export OPENAI_API_KEY="YOUR_OPENAI_API_KEY"
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
2. `~/.transcribe-mini/config.json` (optional)
3. Environment variables (override file/defaults)

Supported environment variables:
- `TRANSCRIBE_PROFILE` (profile name from `profiles` map)
- `TRANSCRIBE_PROVIDER` (`apple`, `openai`, `groq`, `whispercpp`)
- `TRANSCRIBE_API_KEY` (global override)
- `TRANSCRIBE_OPENAI_API_KEY` (OpenAI profile key)
- `TRANSCRIBE_GROQ_API_KEY` (Groq profile key)
- `OPENAI_API_KEY` / `GROQ_API_KEY` (fallback provider keys)
- `TRANSCRIBE_MODEL`
- `TRANSCRIBE_ENDPOINT`
- `TRANSCRIBE_LANGUAGE`
- `TRANSCRIBE_LOCAL_MODEL` (path to local whisper.cpp model; overrides `TRANSCRIBE_MODEL`)
- `WHISPER_CLI_PATH` (default: `/opt/homebrew/bin/whisper-cli`)
- `TRANSCRIBE_USE_WHISPER_SERVER` (`true`/`false`, default: `true`)
- `WHISPER_SERVER_PATH` (default: `/opt/homebrew/bin/whisper-server`)
- `WHISPER_SERVER_HOST` (default: `127.0.0.1`)
- `WHISPER_SERVER_PORT` (default: `8178`)
- `WHISPER_SERVER_INFERENCE_PATH` (default: `/inference`)

Optional file: `~/.transcribe-mini/config.json`.

### Profile-based config (recommended)

```json
{
  "defaultProfile": "openai",
  "profiles": {
    "openai": {
      "provider": "openai",
      "model": "gpt-4o-mini-transcribe",
      "language": "en"
    },
    "apple": {
      "provider": "apple",
      "language": "en-US"
    },
    "groq": {
      "provider": "groq",
      "model": "whisper-large-v3",
      "language": "en"
    },
    "whispercpp": {
      "provider": "whispercpp",
      "model": "/Users/you/.transcribe-mini/models/ggml-base.en.bin",
      "language": "en",
      "useWhisperServer": true,
      "whisperServerPath": "/opt/homebrew/bin/whisper-server",
      "whisperCLIPath": "/opt/homebrew/bin/whisper-cli"
    }
  }
}
```

Set API keys via environment:

```bash
export TRANSCRIBE_OPENAI_API_KEY="YOUR_OPENAI_API_KEY"
export TRANSCRIBE_GROQ_API_KEY="YOUR_GROQ_API_KEY"
```

Profile selection order:
1. `TRANSCRIBE_PROFILE`
2. `defaultProfile`
3. First profile key in sorted order (deterministic fallback)

Switch profile at runtime without editing JSON:

```bash
TRANSCRIBE_PROFILE=apple swift run
```

```bash
TRANSCRIBE_PROFILE=groq GROQ_API_KEY="YOUR_GROQ_API_KEY" swift run
```

You can also switch profiles from the menu bar icon under `Profiles`. The selected profile is remembered for next launch.

### Local whisper.cpp setup example

```bash
brew install whisper-cpp
mkdir -p "$HOME/.transcribe-mini/models"
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin \
  -o "$HOME/.transcribe-mini/models/ggml-base.en.bin"

export TRANSCRIBE_PROVIDER="whispercpp"
export TRANSCRIBE_LOCAL_MODEL="$HOME/.transcribe-mini/models/ggml-base.en.bin"
export TRANSCRIBE_LANGUAGE="en"
export TRANSCRIBE_USE_WHISPER_SERVER="true"
swift run
```

Default local behavior uses persistent `whisper-server` for faster repeated utterances.
First request after app launch can still be slower while the model is loaded into memory.
Fallback to one-shot CLI mode:

```bash
export TRANSCRIBE_USE_WHISPER_SERVER="false"
```

The `base.en` model offers the best speed/quality tradeoff (~0.2s inference for 10s audio with proper casing). For higher quality at the cost of speed:

```bash
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin \
  -o "$HOME/.transcribe-mini/models/ggml-large-v3-turbo-q5_0.bin"

export TRANSCRIBE_LOCAL_MODEL="$HOME/.transcribe-mini/models/ggml-large-v3-turbo-q5_0.bin"
```

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

## Integration Tests (OpenAI/Groq)

Integration tests are opt-in and skipped by default. They make real API calls.

Run with OpenAI:

```bash
RUN_INTEGRATION_TESTS=1 \
TRANSCRIBE_OPENAI_API_KEY="YOUR_OPENAI_API_KEY" \
swift test --filter OpenAICompatibleIntegrationTests/testOpenAITranscriptionIntegration
```

Run with Groq:

```bash
RUN_INTEGRATION_TESTS=1 \
TRANSCRIBE_GROQ_API_KEY="YOUR_GROQ_API_KEY" \
swift test --filter OpenAICompatibleIntegrationTests/testGroqTranscriptionIntegration
```

## Notes

- Menubar icon states:
  - Waveform: idle
  - Red filled waveform: recording
  - Red waveform with magnifier: transcribing
  - Orange warning triangle: last action failed
- Default hold key is hardcoded to `Fn`.
- Recording cues use bundled `dictation-start.wav` and `dictation-stop.wav`.
- Audio is captured as 16kHz mono PCM and packaged as in-memory `.wav` for OpenAI-compatible uploads (no temp file required for upload).
- Final recordings are persisted to `~/.transcribe-mini/recordings/`.
