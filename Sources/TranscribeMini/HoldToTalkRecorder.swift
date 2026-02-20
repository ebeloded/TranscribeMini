@preconcurrency import AVFoundation
import Foundation

enum RecorderError: Error {
    case startFailed
    case setupFailed
}

struct RecordedAudio {
    let data: Data
    let mimeType: String
    let suggestedFilename: String
    let durationSeconds: Double
}

final class HoldToTalkRecorder: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var chunks: [Data] = []
    private var recordedFrameCount: Int64 = 0
    private let chunkQueue = DispatchQueue(label: "com.transcribemini.recorder.chunk-queue")

    func start() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw RecorderError.setupFailed
        }

        chunks.removeAll(keepingCapacity: true)
        recordedFrameCount = 0
        self.converter = converter
        self.targetFormat = targetFormat

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.chunkQueue.async {
                self.captureChunk(from: buffer)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            self.audioEngine = engine
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecorderError.startFailed
        }
    }

    func stop() -> RecordedAudio? {
        guard let engine = audioEngine else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil

        var pcmData = Data()
        var frameCount: Int64 = 0

        chunkQueue.sync {
            pcmData = chunks.reduce(into: Data(), { partialResult, chunk in
                partialResult.append(chunk)
            })
            frameCount = recordedFrameCount
            chunks.removeAll(keepingCapacity: false)
            recordedFrameCount = 0
        }

        converter = nil
        let sampleRate = targetFormat?.sampleRate ?? 16_000
        targetFormat = nil

        guard !pcmData.isEmpty else { return nil }

        let wavData = Self.makeWAVData(
            pcmData: pcmData,
            sampleRate: Int(sampleRate),
            channels: 1,
            bitsPerSample: 16
        )

        let duration = sampleRate > 0 ? Double(frameCount) / sampleRate : 0
        return RecordedAudio(
            data: wavData,
            mimeType: "audio/wav",
            suggestedFilename: "transcribe-mini-\(UUID().uuidString).wav",
            durationSeconds: duration
        )
    }

    private func captureChunk(from buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard frameCapacity > 0 else { return }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCapacity
        ) else {
            return
        }

        final class ConversionState: @unchecked Sendable {
            var didProvideInput = false
        }
        let state = ConversionState()
        var conversionError: NSError?
        _ = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if state.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            state.didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil else { return }
        guard outputBuffer.frameLength > 0 else { return }
        guard let channelData = outputBuffer.int16ChannelData?.pointee else { return }

        let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        let byteCount = Int(outputBuffer.frameLength) * bytesPerFrame
        chunks.append(Data(bytes: channelData, count: byteCount))
        recordedFrameCount += Int64(outputBuffer.frameLength)
    }

    private static func makeWAVData(
        pcmData: Data,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let riffSize = UInt32(36) + dataSize

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: riffSize.littleEndian, Array.init))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)

        let fmtChunkSize: UInt32 = 16
        let audioFormat: UInt16 = 1
        let channelsValue = UInt16(channels)
        let sampleRateValue = UInt32(sampleRate)
        let byteRateValue = UInt32(byteRate)
        let blockAlignValue = UInt16(blockAlign)
        let bitsPerSampleValue = UInt16(bitsPerSample)

        header.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: channelsValue.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: sampleRateValue.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: byteRateValue.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: blockAlignValue.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSampleValue.littleEndian, Array.init))

        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        var wavData = Data()
        wavData.reserveCapacity(header.count + pcmData.count)
        wavData.append(header)
        wavData.append(pcmData)
        return wavData
    }
}
