import Foundation

actor WhisperServerManager {
    static let shared = WhisperServerManager()

    private struct RuntimeConfig: Equatable {
        let serverPath: String
        let modelPath: String
        let host: String
        let port: Int
    }

    private var process: Process?
    private var config: RuntimeConfig?

    func ensureRunning(serverPath: String, modelPath: String, host: String, port: Int) async throws {
        let next = RuntimeConfig(serverPath: serverPath, modelPath: modelPath, host: host, port: port)

        if let process,
           process.isRunning,
           config == next,
           await isResponsive(host: host, port: port) {
            return
        }

        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = [
            "--model", modelPath,
            "--host", host,
            "--port", "\(port)"
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()

        self.process = process
        self.config = next

        try await waitUntilResponsive(host: host, port: port, timeoutNanoseconds: 25_000_000_000)
    }

    func stop() {
        guard let process else { return }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        self.process = nil
        config = nil
    }

    private func waitUntilResponsive(host: String, port: Int, timeoutNanoseconds: UInt64) async throws {
        let start = ContinuousClock.now

        while start.duration(to: .now) < .nanoseconds(Int64(timeoutNanoseconds)) {
            if await isResponsive(host: host, port: port) {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        throw NSError(domain: "WhisperServerManager", code: 20, userInfo: [
            NSLocalizedDescriptionKey: "whisper-server failed to become ready"
        ])
    }

    private func isResponsive(host: String, port: Int) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ... 299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
