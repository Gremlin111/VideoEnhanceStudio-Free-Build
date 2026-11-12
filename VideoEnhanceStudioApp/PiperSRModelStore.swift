import Foundation
import CoreML
import CryptoKit

/// Installs genuine trained PiperSR model weights, on demand, from the model publisher.
/// Only the model is downloaded. User videos are NEVER sent to this or any server.
/// Licensed CC BY 4.0: PiperSR by Ben Racicot / ModelPiper (https://modelpiper.com).
enum PiperSRModelStore {
    private static let version = "pipersr-2x-7bc566a"
    private static let revision = "7bc566a63a11ae63f71b90d57f3c4280802ce444"
    private static let baseURL = "https://huggingface.co/ModelPiper/PiperSR-2x/resolve/\(revision)/PiperSR_2x.mlpackage/"

    static var compiledURL: URL {
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("\(version).mlmodelc", isDirectory: true)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: compiledURL.path)
    }

    static func install() async throws {
        if isInstalled { return }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("PiperSR-\(UUID().uuidString)", isDirectory: true)
        let sourcePackage = staging.appendingPathComponent("PiperSR_2x.mlpackage", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: sourcePackage, withIntermediateDirectories: true)

        // These are the exact files present in the publisher's Core ML package.
        // SHA-256 checks detect incomplete/corrupt and unexpected model downloads.
        let files: [(path: String, sha256: String?)] = [
            ("Manifest.json", nil),
            ("Data/com.apple.CoreML/model.mlmodel", "df7fcedd18b75f7e87a9d782e65efb00a946947f30a877ee5e6ba6e23d263a9f"),
            ("Data/com.apple.CoreML/weights/weight.bin", "470924d59790b031487863da4f0df0a394c05cb959455300e78484754841e060")
        ]

        for file in files {
            guard let url = URL(string: baseURL + file.path) else {
                throw ModelInstallError.badURL
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 45
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw ModelInstallError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            guard bytes.count > 100 else { throw ModelInstallError.incompleteDownload }
            if let expected = file.sha256 {
                let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw ModelInstallError.checksumMismatch }
            }
            let destination = sourcePackage.appendingPathComponent(file.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: destination, options: .atomic)
        }

        // Core ML compiles the trusted .mlpackage ON THE IPAD once.
        let compiledTemporary = try await Task.detached(priority: .userInitiated) {
            try MLModel.compileModel(at: sourcePackage)
        }.value
        // Load the compiled model before marking the install as complete.
        // A failed compile/load must not leave a misleading "Ready" state.
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        _ = try MLModel(contentsOf: compiledTemporary, configuration: config)

        let persistent = compiledURL
        try fm.createDirectory(at: persistent.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: persistent.path) { try fm.removeItem(at: persistent) }
        try fm.moveItem(at: compiledTemporary, to: persistent)
    }
}

private enum ModelInstallError: LocalizedError {
    case badURL, incompleteDownload, checksumMismatch, httpError(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The model URL is invalid."
        case .incompleteDownload: return "The model download was incomplete. Connect to Wi-Fi and try again."
        case .checksumMismatch: return "The downloaded AI model failed its security check. Please try again."
        case .httpError(let code): return "Model download failed (HTTP \(code)). Check your internet connection."
        }
    }
}
