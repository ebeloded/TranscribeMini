import Foundation

// MARK: - Models & Config

struct BenchmarkResult {
    let name: String
    let duration: String
    let loadTime: Double?
    let avgInference: Double
    let text: String
}

struct AudioSample {
    let label: String
    let wavPath: String
}

let modelsDir: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/.transcribe-mini/models"
}()

let localModels = [
    "ggml-tiny.en.bin",
    "ggml-base.en.bin",
    "ggml-small.en.bin",
    "ggml-large-v3-turbo-q5_0.bin",
]

let huggingFaceBase = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

let whisperServerPath = "/opt/homebrew/bin/whisper-server"
let serverHost = "127.0.0.1"
let serverPort = 8179 // Use a different port from the main app

let speechTexts: [(label: String, text: String)] = [
    ("~10s", """
    The quick brown fox jumps over the lazy dog. \
    Today we are testing the transcription speed of various models \
    to find the best tradeoff between speed and quality.
    """),
    ("~30s", """
    The quick brown fox jumps over the lazy dog. \
    Today we are testing the transcription speed of various whisper models \
    to find the best tradeoff between speed and quality. \
    This is a sample of natural English speech for benchmarking purposes. \
    We want to see how each model handles longer passages of continuous speech. \
    The results will help us decide which model to use in production. \
    Smaller models tend to be faster but may sacrifice accuracy, \
    while larger models are more accurate but require more computation time. \
    Finding the right balance is key to a good user experience.
    """),
    ("~60s", """
    The quick brown fox jumps over the lazy dog. \
    Today we are testing the transcription speed of various whisper models \
    to find the best tradeoff between speed and quality. \
    This is a longer sample of natural English speech for benchmarking purposes. \
    We want to see how each model handles extended passages of continuous speech, \
    because real world usage often involves longer dictation sessions. \
    The results will help us decide which model to use in production environments. \
    Smaller models tend to be faster but may sacrifice accuracy on complex sentences, \
    while larger models are more accurate but require significantly more computation time. \
    Finding the right balance is key to providing a good user experience. \
    In practice, users often dictate emails, messages, and notes that can range from \
    a few words to several paragraphs. The model needs to handle all of these cases well. \
    Background noise, accents, and speaking pace also affect transcription quality. \
    We should consider these factors when choosing our default model. \
    A model that works well in quiet environments may struggle in noisy ones. \
    Ultimately, the best model is one that provides accurate results quickly enough \
    that the user does not notice any delay in their workflow. \
    Let us now proceed with the benchmark and examine the results carefully.
    """),
]

// MARK: - Audio Generation

func generateTTSSamples() throws -> [AudioSample] {
    print("Generating TTS audio samples...")
    var samples: [AudioSample] = []

    for (i, entry) in speechTexts.enumerated() {
        let aiffPath = "/tmp/transcribe-bench-\(i).aiff"
        let wavPath = "/tmp/transcribe-bench-\(i).wav"
        try runProcess("/usr/bin/say", args: ["-v", "Daniel", "-o", aiffPath, entry.text])
        try runProcess("/opt/homebrew/bin/sox", args: [aiffPath, "-r", "16000", "-c", "1", "-b", "16", wavPath])
        let attrs = try FileManager.default.attributesOfItem(atPath: wavPath)
        let size = (attrs[.size] as? Int) ?? 0
        let durationSec = Double(size - 44) / (16000.0 * 2) // 16kHz, 16-bit mono
        print("  \(entry.label): \(wavPath) (\(size) bytes, \(String(format: "%.1f", durationSec))s)")
        samples.append(AudioSample(label: entry.label, wavPath: wavPath))
    }

    return samples
}

func recordMicSample(seconds: Int) throws -> AudioSample {
    let wavPath = "/tmp/transcribe-bench-mic.wav"
    print("\n  Recording from microphone for \(seconds) seconds...")
    print("  Speak now!")

    // Use sox to record from default mic
    try runProcess("/opt/homebrew/bin/sox", args: [
        "-d",               // default audio device
        "-r", "16000",      // 16kHz
        "-c", "1",          // mono
        "-b", "16",         // 16-bit
        wavPath,
        "trim", "0", "\(seconds)",
    ])

    let attrs = try FileManager.default.attributesOfItem(atPath: wavPath)
    let size = (attrs[.size] as? Int) ?? 0
    print("  Recorded \(size) bytes")
    return AudioSample(label: "mic-\(seconds)s", wavPath: wavPath)
}

// MARK: - Model Download

func ensureModelsDownloaded() async throws {
    try FileManager.default.createDirectory(atPath: modelsDir, withIntermediateDirectories: true)

    for model in localModels {
        let path = "\(modelsDir)/\(model)"
        if FileManager.default.fileExists(atPath: path) {
            print("  Model \(model) -- already downloaded")
            continue
        }

        let url = URL(string: "\(huggingFaceBase)/\(model)")!
        print("  Downloading \(model)...")
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BenchError.downloadFailed(model)
        }
        try FileManager.default.moveItem(atPath: tempURL.path, toPath: path)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int) ?? 0
        let mb = Double(size) / 1_048_576.0
        print("  Downloaded \(model) (\(String(format: "%.1f", mb)) MB)")
    }
}

// MARK: - Whisper Server Management

func stopWhisperServer() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    task.arguments = ["-f", "whisper-server.*--port \(serverPort)"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.5)
}

func startWhisperServer(modelPath: String) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: whisperServerPath)
    process.arguments = [
        "--model", modelPath,
        "--host", serverHost,
        "--port", "\(serverPort)",
        "--flash-attn",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process
}

func waitForServer(timeoutSeconds: Double = 30) async throws {
    let start = ContinuousClock.now
    let url = URL(string: "http://\(serverHost):\(serverPort)/")!

    while start.duration(to: .now) < .seconds(timeoutSeconds) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse,
           (200...299).contains(http.statusCode) {
            return
        }
        try await Task.sleep(nanoseconds: 200_000_000)
    }
    throw BenchError.serverTimeout
}

// MARK: - Transcription Requests

func transcribeViaWhisperServer(wavPath: String) async throws -> String {
    let url = URL(string: "http://\(serverHost):\(serverPort)/inference")!
    let boundary = "Boundary-\(UUID().uuidString)"

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 120

    let audioData = try Data(contentsOf: URL(fileURLWithPath: wavPath))
    var body = Data()
    body.appendField(name: "language", value: "en", boundary: boundary)
    body.appendField(name: "response_format", value: "json", boundary: boundary)
    body.appendField(name: "temperature", value: "0.0", boundary: boundary)
    body.appendFile(name: "file", filename: "bench.wav", mimeType: "audio/wav", data: audioData, boundary: boundary)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)

    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let msg = String(data: data, encoding: .utf8) ?? "request failed"
        throw BenchError.transcriptionFailed(msg)
    }

    let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func transcribeViaOpenAI(wavPath: String, apiKey: String) async throws -> String {
    let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    let boundary = "Boundary-\(UUID().uuidString)"

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 120

    let audioData = try Data(contentsOf: URL(fileURLWithPath: wavPath))
    var body = Data()
    body.appendField(name: "model", value: "gpt-4o-mini-transcribe", boundary: boundary)
    body.appendField(name: "language", value: "en", boundary: boundary)
    body.appendFile(name: "file", filename: "bench.wav", mimeType: "audio/wav", data: audioData, boundary: boundary)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)

    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let msg = String(data: data, encoding: .utf8) ?? "request failed"
        throw BenchError.transcriptionFailed(msg)
    }

    let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Benchmark Runner

func benchmarkLocalModel(_ model: String, samples: [AudioSample]) async throws -> [BenchmarkResult] {
    let modelPath = "\(modelsDir)/\(model)"
    let displayName = "local/\(model.replacingOccurrences(of: ".bin", with: ""))"

    print("  Benchmarking \(displayName)...")

    // Stop any existing server
    stopWhisperServer()

    // Start server and measure load time
    let loadStart = ContinuousClock.now
    let process = try startWhisperServer(modelPath: modelPath)
    try await waitForServer()
    let loadTime = loadStart.duration(to: .now).seconds

    // Warmup request
    _ = try await transcribeViaWhisperServer(wavPath: samples[0].wavPath)

    var results: [BenchmarkResult] = []

    for sample in samples {
        print("    [\(sample.label)]")
        var times: [Double] = []
        var lastText = ""
        for i in 1...3 {
            let start = ContinuousClock.now
            let text = try await transcribeViaWhisperServer(wavPath: sample.wavPath)
            let elapsed = start.duration(to: .now).seconds
            times.append(elapsed)
            lastText = text
            print("      Run \(i): \(String(format: "%.3f", elapsed))s")
        }
        let avg = times.reduce(0, +) / Double(times.count)
        results.append(BenchmarkResult(
            name: displayName,
            duration: sample.label,
            loadTime: results.isEmpty ? loadTime : nil, // only show load time on first row
            avgInference: avg,
            text: lastText
        ))
    }

    // Stop server
    process.terminate()
    process.waitUntilExit()

    return results
}

func benchmarkOpenAI(apiKey: String, samples: [AudioSample]) async throws -> [BenchmarkResult] {
    let displayName = "openai/gpt-4o-mini-transcribe"
    print("  Benchmarking \(displayName)...")

    // Warmup
    _ = try await transcribeViaOpenAI(wavPath: samples[0].wavPath, apiKey: apiKey)

    var results: [BenchmarkResult] = []

    for sample in samples {
        print("    [\(sample.label)]")
        var times: [Double] = []
        var lastText = ""
        for i in 1...3 {
            let start = ContinuousClock.now
            let text = try await transcribeViaOpenAI(wavPath: sample.wavPath, apiKey: apiKey)
            let elapsed = start.duration(to: .now).seconds
            times.append(elapsed)
            lastText = text
            print("      Run \(i): \(String(format: "%.3f", elapsed))s")
        }
        let avg = times.reduce(0, +) / Double(times.count)
        results.append(BenchmarkResult(
            name: displayName,
            duration: sample.label,
            loadTime: nil,
            avgInference: avg,
            text: lastText
        ))
    }

    return results
}

// MARK: - Output

func printResults(_ results: [BenchmarkResult]) {
    let nameWidth = 38
    let durWidth = 10
    let loadWidth = 9
    let inferWidth = 15
    let textWidth = 45

    let divider = String(repeating: "-", count: nameWidth)
        + "|" + String(repeating: "-", count: durWidth)
        + "|" + String(repeating: "-", count: loadWidth)
        + "|" + String(repeating: "-", count: inferWidth)
        + "|" + String(repeating: "-", count: textWidth)

    print()
    print(pad("Provider/Model", nameWidth)
        + "|" + pad("Audio", durWidth)
        + "|" + pad("Load", loadWidth)
        + "|" + pad("Avg Inference", inferWidth)
        + "|" + " Text")
    print(divider)

    for r in results {
        let loadStr: String
        if let lt = r.loadTime {
            loadStr = String(format: "%.2fs", lt)
        } else {
            loadStr = ""
        }
        let inferStr = String(format: "%.3fs", r.avgInference)
        let cleanText = r.text.replacingOccurrences(of: "\n", with: " ")
        let truncatedText = cleanText.count > textWidth
            ? String(cleanText.prefix(textWidth - 3)) + "..."
            : cleanText

        print(pad(r.name, nameWidth)
            + "|" + pad(r.duration, durWidth)
            + "|" + pad(loadStr, loadWidth)
            + "|" + pad(inferStr, inferWidth)
            + "| " + truncatedText)
    }
    print()
}

// MARK: - Helpers

struct TranscriptionResponse: Decodable {
    let text: String
}

enum BenchError: Error, CustomStringConvertible {
    case downloadFailed(String)
    case serverTimeout
    case transcriptionFailed(String)
    case missingDependency(String)

    var description: String {
        switch self {
        case .downloadFailed(let m): return "Failed to download model: \(m)"
        case .serverTimeout: return "Whisper server failed to start within timeout"
        case .transcriptionFailed(let m): return "Transcription failed: \(m)"
        case .missingDependency(let m): return "Missing dependency: \(m)"
        }
    }
}

func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return " " + s + String(repeating: " ", count: width - s.count - 1)
}

func runProcess(_ path: String, args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let errPipe = Pipe()
    process.standardError = errPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errData, encoding: .utf8) ?? "unknown error"
        throw BenchError.missingDependency("\(path) failed: \(errText)")
    }
}

extension Data {
    mutating func appendFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}

extension Duration {
    var seconds: Double {
        let (s, atto) = components
        return Double(s) + Double(atto) * 1e-18
    }
}

// MARK: - CLI Parsing

func printUsage() {
    print("""
    Usage: TranscribeBench [options]

    Options:
      --mic <seconds>   Record from microphone for the given duration and
                         include it as an additional audio sample
      --help            Show this help message

    Environment:
      OPENAI_API_KEY    Set to include OpenAI API benchmark
    """)
}

// MARK: - Main

@main
struct TranscribeBench {
    static func main() async throws {
        let args = CommandLine.arguments.dropFirst()

        var micSeconds: Int? = nil
        var i = args.startIndex
        while i < args.endIndex {
            switch args[i] {
            case "--help", "-h":
                printUsage()
                return
            case "--mic":
                let next = args.index(after: i)
                guard next < args.endIndex, let secs = Int(args[next]), secs > 0 else {
                    print("ERROR: --mic requires a positive integer (seconds)")
                    Foundation.exit(1)
                }
                micSeconds = secs
                i = args.index(after: next)
            default:
                print("Unknown option: \(args[i])")
                printUsage()
                Foundation.exit(1)
            }
        }

        print("=== Transcription Speed Benchmark ===\n")

        // Check dependencies
        guard FileManager.default.fileExists(atPath: whisperServerPath) else {
            print("ERROR: whisper-server not found at \(whisperServerPath)")
            print("Install with: brew install whisper-cpp")
            Foundation.exit(1)
        }

        guard FileManager.default.fileExists(atPath: "/opt/homebrew/bin/sox") else {
            print("ERROR: sox not found at /opt/homebrew/bin/sox")
            print("Install with: brew install sox")
            Foundation.exit(1)
        }

        // Generate TTS audio samples (10s, 30s, 60s)
        var samples = try generateTTSSamples()

        // Optionally record from microphone
        if let micSeconds {
            let micSample = try recordMicSample(seconds: micSeconds)
            samples.append(micSample)
        }

        // Ensure models are downloaded
        print("\nChecking models...")
        try await ensureModelsDownloaded()

        var results: [BenchmarkResult] = []

        // OpenAI benchmark
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        if !apiKey.isEmpty {
            print("\nRunning OpenAI benchmark...")
            do {
                let openaiResults = try await benchmarkOpenAI(apiKey: apiKey, samples: samples)
                results.append(contentsOf: openaiResults)
            } catch {
                print("  OpenAI benchmark failed: \(error)")
            }
        } else {
            print("\nSkipping OpenAI benchmark (OPENAI_API_KEY not set)")
        }

        // Warm up whisper-server binary
        print("\nWarming up whisper-server...")
        do {
            let warmupModel = "\(modelsDir)/\(localModels[0])"
            let p = try startWhisperServer(modelPath: warmupModel)
            try await waitForServer()
            p.terminate()
            p.waitUntilExit()
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Local model benchmarks
        print("\nRunning local model benchmarks...")
        for model in localModels {
            do {
                let modelResults = try await benchmarkLocalModel(model, samples: samples)
                results.append(contentsOf: modelResults)
            } catch {
                print("  Benchmark for \(model) failed: \(error)")
            }
        }

        // Clean up
        stopWhisperServer()

        // Print results
        print("\n=== Results ===")
        printResults(results)
    }
}
