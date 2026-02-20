# TranscribeMini

A minimal macOS hold-to-talk transcription app.

Interaction:
- Hold `Fn`: recording starts immediately.
- Release `Fn`: recording stops, audio is transcribed, text is pasted at your cursor.

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
- `TRANSCRIBE_USE_WHISPER_SERVER` (`true`/`false`, default: `true`)
- `WHISPER_SERVER_PATH` (default: `/opt/homebrew/bin/whisper-server`)
- `WHISPER_SERVER_HOST` (default: `127.0.0.1`)
- `WHISPER_SERVER_PORT` (default: `8178`)
- `WHISPER_SERVER_INFERENCE_PATH` (default: `/inference`)

Optional file: `~/.transcribe-mini.json`.

### OpenAI hosted transcription (default)

```json
{
  "provider": "openai",
  "apiKey": "YOUR_OPENAI_API_KEY",
  "model": "gpt-4o-mini-transcribe",
  "language": "en"
}
```

### Local Apple Speech

```json
{
  "provider": "apple",
  "apiKey": "",
  "model": "gpt-4o-mini-transcribe",
  "language": "en-US"
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

## Notes

- Menubar icon states:
  - Waveform: idle
  - Red filled waveform: recording
  - Red waveform with magnifier: transcribing
  - Orange warning triangle: last action failed
- Default hold key is hardcoded to `Fn`.
- Audio is captured as 16kHz mono PCM and packaged as in-memory `.wav` for OpenAI-compatible uploads (no temp file required for upload).
- Final recordings are persisted to `~/.transcribe-mini/recordings/`.
