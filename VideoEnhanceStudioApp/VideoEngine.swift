import Foundation
import Combine
import AVFoundation
import AVKit
import CoreImage
import CoreVideo
import CoreMedia

@MainActor
final class UpscaleViewModel: ObservableObject {
    @Published var inputURL: URL?
    @Published var outputURL: URL?
    @Published var player: AVPlayer?
    @Published var isProcessing = false
    @Published var progress = 0.0
    @Published var isInstallingAI = false
    @Published var hasAIModel = PiperSRModelStore.isInstalled
    @Published var errorMessage: String?

    private var cancellation = CancellationFlag()

    func report(_ message: String) { errorMessage = message }

    func loadVideo(from selectedURL: URL) {
        let allowed = selectedURL.startAccessingSecurityScopedResource()
        defer { if allowed { selectedURL.stopAccessingSecurityScopedResource() } }
        do {
            let ext = selectedURL.pathExtension.isEmpty ? "mov" : selectedURL.pathExtension
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("source-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: selectedURL, to: localURL)
            player?.pause()
            inputURL = localURL
            outputURL = nil
            player = AVPlayer(url: localURL)
            progress = 0
        } catch {
            errorMessage = "Cannot import video: \(error.localizedDescription). Check that your iPad has enough free storage."
        }
    }

    func installAIModel() {
        guard !isInstallingAI && !isProcessing else { return }
        isInstallingAI = true
        Task {
            do {
                try await PiperSRModelStore.install()
                hasAIModel = true
            } catch {
                // Don't allow an interrupted or invalid install to masquerade as ready.
                hasAIModel = false
                errorMessage = "Could not install AI model: \(error.localizedDescription)"
            }
            isInstallingAI = false
        }
    }

    func enhance(factor: Int, sharpness: Double, noise: Double, useAI: Bool) {
        if useAI && !hasAIModel {
            errorMessage = "Install the AI model first. It then runs completely offline."
            return
        }
        guard let sourceURL = inputURL, !isProcessing else { return }
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("enhanced-\(UUID().uuidString).mp4")
        let cancellation = CancellationFlag()
        self.cancellation = cancellation
        outputURL = nil
        isProcessing = true
        progress = 0
        player?.pause()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try VideoExporter.export(
                    sourceURL: sourceURL,
                    destinationURL: targetURL,
                    factor: factor,
                    sharpness: sharpness,
                    noise: noise,
                    aiModelURL: useAI ? PiperSRModelStore.compiledURL : nil,
                    cancellation: cancellation
                ) { fraction in
                    DispatchQueue.main.async { [weak self] in
                        self?.progress = fraction
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProcessing = false
                switch result {
                case .success:
                    self.progress = 1
                    self.outputURL = targetURL
                    self.player = AVPlayer(url: targetURL)
                case .failure(let error):
                    self.progress = 0
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancel() { cancellation.cancel() }
}

final class CancellationFlag {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private final class FailureBox {
    private let lock = NSLock()
    private var storedError: Error?

    func store(_ error: Error) {
        lock.lock()
        if storedError == nil { storedError = error }
        lock.unlock()
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

private enum ExportError: LocalizedError {
    case noVideo
    case invalidSize
    case exceeds4K
    case setup(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noVideo: return "This file does not contain a supported video track."
        case .invalidSize: return "The source video has invalid frame dimensions."
        case .exceeds4K: return "This setting would produce a video above 4K. Choose a smaller upscale factor."
        case .setup(let message): return "Cannot start export: \(message)"
        case .cancelled: return "Export cancelled."
        case .failed(let message): return "Export failed: \(message)"
        }
    }
}

private enum VideoExporter {
    static func export(
        sourceURL: URL,
        destinationURL: URL,
        factor: Int,
        sharpness: Double,
        noise: Double,
        aiModelURL: URL?,
        cancellation: CancellationFlag,
        progress: @escaping (Double) -> Void
    ) throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw ExportError.noVideo
        }
        let sourceWidth = Int(abs(track.naturalSize.width).rounded())
        let sourceHeight = Int(abs(track.naturalSize.height).rounded())
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ExportError.invalidSize
        }

        // H.264 encoders generally expect even output dimensions.
        let outputWidth = ((sourceWidth * factor + 1) / 2) * 2
        let outputHeight = ((sourceHeight * factor + 1) / 2) * 2
        let longest = max(outputWidth, outputHeight)
        let shortest = min(outputWidth, outputHeight)
        guard longest <= 3840 && shortest <= 2160 else {
            throw ExportError.exceeds4K
        }
        guard !cancellation.isCancelled else { throw ExportError.cancelled }

        // The dedicated AI model is loaded once per export; no cloud video inference.
        let aiProcessor = try aiModelURL.map { try PiperSRProcessor(compiledURL: $0) }

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ExportError.setup("Video decoder unavailable") }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)
        let pixelCount = outputWidth * outputHeight
        let bitrate = pixelCount <= 1920 * 1080 ? 12_000_000 : (pixelCount <= 2560 * 1440 ? 20_000_000 : 35_000_000)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        // Preferred transforms must scale their translation for the enlarged video.
        let transform = track.preferredTransform
        videoInput.transform = CGAffineTransform(
            a: transform.a, b: transform.b,
            c: transform.c, d: transform.d,
            tx: transform.tx * CGFloat(factor),
            ty: transform.ty * CGFloat(factor)
        )
        guard writer.canAdd(videoInput) else { throw ExportError.setup("H.264 encoder unavailable") }
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            // Decode to PCM and encode AAC for .mp4 audio compatibility.
            // AVAssetTrack.formatDescriptions is imported as [Any], but the items
            // are Core Media format descriptions. Cast the entire array, as in
            // Apple's AVAssetTrack.formatDescriptions documentation. Using `as?`
            // on a CoreFoundation type is diagnosed as an error by Swift.
            let formats = audioTrack.formatDescriptions as! [CMFormatDescription]
            let asbd = formats.first.flatMap {
                CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
            }
            let sampleRate = asbd?.mSampleRate ?? 44100
            let channels = max(1, Int(asbd?.mChannelsPerFrame ?? 2))
            let readerAudio = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            let writerAudio = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000
                ]
            )
            writerAudio.expectsMediaDataInRealTime = false
            if reader.canAdd(readerAudio) && writer.canAdd(writerAudio) {
                reader.add(readerAudio)
                writer.add(writerAudio)
                audioOutput = readerAudio
                audioInput = writerAudio
            } else {
                throw ExportError.setup("Cannot configure the video's audio track")
            }
        }

        guard writer.startWriting() else {
            throw ExportError.setup(writer.error?.localizedDescription ?? "Cannot start encoder")
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw ExportError.setup(reader.error?.localizedDescription ?? "Cannot start decoder")
        }

        let failure = FailureBox()
        let group = DispatchGroup()
        let duration = max(0.001, asset.duration.seconds.isFinite ? asset.duration.seconds : 1)
        let outputSize = CGSize(width: outputWidth, height: outputHeight)

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                videoInput.markAsFinished()
                group.leave()
            }
            let context = CIContext(options: [
                .useSoftwareRenderer: false,
                .cacheIntermediates: false
            ])
            var frame = 0
            while !cancellation.isCancelled && failure.error == nil,
                  let sample = videoOutput.copyNextSampleBuffer() {
                guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else {
                    failure.store(ExportError.failed("Cannot decode a video frame"))
                    break
                }
                while !videoInput.isReadyForMoreMediaData && !cancellation.isCancelled && failure.error == nil {
                    Thread.sleep(forTimeInterval: 0.006)
                }
                if cancellation.isCancelled || failure.error != nil { break }
                guard let pool = adaptor.pixelBufferPool else {
                    failure.store(ExportError.failed("Cannot allocate output frame pool"))
                    break
                }
                var outputBuffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
                guard status == kCVReturnSuccess, let outputBuffer else {
                    failure.store(ExportError.failed("Not enough memory for video frames"))
                    break
                }

                var image = CIImage(cvPixelBuffer: sourceBuffer)
                if noise > 0.001 {
                    image = image.applyingFilter("CINoiseReduction", parameters: [
                        "inputNoiseLevel": noise,
                        "inputSharpness": 0.2
                    ])
                }
                if let aiProcessor {
                    // REAL neural inference per frame (PiperSR 2×).
                    do {
                        image = try aiProcessor.upscale(image, width: sourceWidth,
                                                       height: sourceHeight, cancellation: cancellation)
                    } catch {
                        failure.store(ExportError.failed("AI processing: \(error.localizedDescription)"))
                        break
                    }
                } else if factor > 1 {
                    image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                        kCIInputScaleKey: Double(factor),
                        kCIInputAspectRatioKey: 1.0
                    ])
                }
                if sharpness > 0.001 {
                    image = image.applyingFilter("CISharpenLuminance", parameters: [
                        kCIInputSharpnessKey: sharpness
                    ])
                }
                // Put the filtered frame at zero origin before rendering.
                image = image.transformed(by: CGAffineTransform(
                    translationX: -image.extent.minX,
                    y: -image.extent.minY
                ))
                context.render(
                    image,
                    to: outputBuffer,
                    bounds: CGRect(origin: .zero, size: outputSize),
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
                if !adaptor.append(outputBuffer, withPresentationTime: timestamp) {
                    failure.store(ExportError.failed(writer.error?.localizedDescription ?? "Video encoder rejected a frame"))
                    break
                }
                frame += 1
                if frame % 12 == 0 {
                    let seconds = CMTimeGetSeconds(timestamp)
                    if seconds.isFinite {
                        progress(min(0.98, max(0, seconds / duration)))
                    }
                }
            }
            if reader.status == .failed {
                failure.store(ExportError.failed(reader.error?.localizedDescription ?? "Video decoder stopped"))
            }
        }

        if let audioOutput, let audioInput {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    audioInput.markAsFinished()
                    group.leave()
                }
                while !cancellation.isCancelled && failure.error == nil,
                      let sample = audioOutput.copyNextSampleBuffer() {
                    while !audioInput.isReadyForMoreMediaData && !cancellation.isCancelled && failure.error == nil {
                        Thread.sleep(forTimeInterval: 0.006)
                    }
                    if cancellation.isCancelled || failure.error != nil { break }
                    if !audioInput.append(sample) {
                        failure.store(ExportError.failed(writer.error?.localizedDescription ?? "Audio encoder rejected a sample"))
                        break
                    }
                }
            }
        }

        group.wait()
        if cancellation.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destinationURL)
            throw ExportError.cancelled
        }
        if let error = failure.error {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw ExportError.failed(reader.error?.localizedDescription ?? "Decoder failed")
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw ExportError.failed(writer.error?.localizedDescription ?? "Could not finish encoding")
        }
        progress(1)
    }
}
