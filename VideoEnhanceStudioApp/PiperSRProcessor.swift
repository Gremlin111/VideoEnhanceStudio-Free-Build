import Foundation
import CoreML
import CoreImage
import CoreVideo

/// Actual neural-network super-resolution: model inference is run on every video frame.
/// PiperSR expects 128x128 RGB input tiles and returns 256x256 RGB tiles.
/// An 8-pixel overlapping context on each side reduces visible tile seams.
final class PiperSRProcessor {
    private let model: MLModel
    private let tileSize = 128
    private let border = 8
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let rgbSpace = CGColorSpaceCreateDeviceRGB()
    private let inputBuffer: CVPixelBuffer

    init(compiledURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        self.model = try MLModel(contentsOf: compiledURL, configuration: config)
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 128, 128,
                                         kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw PiperSRError.noMemory }
        self.inputBuffer = buffer
    }

    /// Returns a lazily composited 2x CIImage containing *real* Core ML predictions.
    /// This is called for each frame in the video writer, not just the preview.
    func upscale(_ input: CIImage, width: Int, height: Int, cancellation: CancellationFlag) throws -> CIImage {
        let scale = 2
        let step = tileSize - 2 * border
        let targetBounds = CGRect(x: 0, y: 0, width: width * scale, height: height * scale)
        var canvas = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: targetBounds)
        let padded = input.clampedToExtent()

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                if cancellation.isCancelled { throw PiperSRError.cancelled }

                let sampleRegion = CGRect(x: x - border, y: y - border, width: tileSize, height: tileSize)
                let cropped = padded.cropped(to: sampleRegion).transformed(by:
                    CGAffineTransform(translationX: -sampleRegion.minX, y: -sampleRegion.minY))
                context.render(cropped, to: inputBuffer,
                               bounds: CGRect(x: 0, y: 0, width: 128, height: 128),
                               colorSpace: rgbSpace)

                let features = try MLDictionaryFeatureProvider(dictionary: [
                    "input_image": MLFeatureValue(pixelBuffer: inputBuffer)
                ])
                let prediction = try model.prediction(from: features)
                guard let enhancedBuffer = prediction.featureValue(for: "output_image")?.imageBufferValue else {
                    throw PiperSRError.invalidModelOutput
                }
                let tileOutput = CIImage(cvPixelBuffer: enhancedBuffer)

                // Discard the tile's padded border; write only its unique core.
                let copyWidth = min(step, width - x) * scale
                let copyHeight = min(step, height - y) * scale
                let keep = CGRect(x: border * scale, y: border * scale,
                                  width: copyWidth, height: copyHeight)
                let piece = tileOutput.cropped(to: keep).transformed(by:
                    CGAffineTransform(translationX: CGFloat(x * scale) - keep.minX,
                                      y: CGFloat(y * scale) - keep.minY))
                canvas = piece.composited(over: canvas)
            }
        }
        return canvas.cropped(to: targetBounds)
    }
}

private enum PiperSRError: LocalizedError {
    case noMemory, invalidModelOutput, cancelled

    var errorDescription: String? {
        switch self {
        case .noMemory: return "Not enough memory for an AI video frame."
        case .invalidModelOutput: return "The AI model produced an unexpected output."
        case .cancelled: return "AI upscale cancelled."
        }
    }
}
