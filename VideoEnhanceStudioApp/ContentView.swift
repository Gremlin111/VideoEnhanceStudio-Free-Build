import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = UpscaleViewModel()
    @State private var showImporter = false
    @State private var multiplier = 2
    @State private var useAI = true
    @State private var sharpness = 0.40
    @State private var noiseReduction = 0.02

    private var selectedVideo: URL? { model.outputURL ?? model.inputURL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    introduction
                    videoCard
                    aiModelCard
                    controlsCard
                    exportCard
                    Text("Private by design • Videos stay on your iPad • No account required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 760)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Video Enhance Studio")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { model.loadVideo(from: url) }
                case .failure(let error):
                    model.report(error.localizedDescription)
                }
            }
            .alert("Video processing", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
        }
        .tint(.indigo)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("OFFLINE VIDEO ENHANCEMENT", systemImage: "sparkles.tv")
                .font(.caption.bold())
                .foregroundStyle(.indigo)
            Text("Make your videos look better.")
                .font(.system(size: 29, weight: .bold, design: .rounded))
            Text("Real neural AI 2× upscaling with PiperSR, or classic enhancement. Videos stay on your iPad; audio is preserved when supported.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("VIDEO", systemImage: "film.stack")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.inputURL != nil {
                    Text(model.inputURL?.lastPathComponent ?? "")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            if let player = model.player {
                VideoPlayer(player: player)
                    .frame(height: 320)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                if model.outputURL != nil {
                    Label("Showing enhanced export", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Original video preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.black.opacity(0.9))
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "play.rectangle.on.rectangle")
                                .font(.system(size: 50))
                            Text("Choose a video to get started")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(height: 260)
            }
            Button {
                showImporter = true
            } label: {
                Label(model.inputURL == nil ? "Import video" : "Choose another video", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isProcessing)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var aiModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI MODEL", systemImage: "brain")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.hasAIModel {
                    Label("Ready offline", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                } else {
                    Label("Not installed", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("PiperSR 2× • Dedicated Core ML neural network")
                .font(.headline)
            if !model.hasAIModel {
                Text("Download the trained model once (~0.9 MB). Your videos will never be uploaded. An internet connection is needed only for this initial installation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if model.isInstallingAI {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Downloading, verifying and compiling the AI model…")
                            .font(.subheadline)
                    }
                } else {
                    Button { model.installAIModel() } label: {
                        Label("Install free AI model", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isProcessing)
                }
            } else {
                Text("Ready for 2× AI video enhancement without internet, accounts, or subscriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Model attribution: PiperSR by Ben Racicot / ModelPiper (CC BY 4.0)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Link("About PiperSR", destination: URL(string: "https://modelpiper.com")!)
                .font(.caption)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("ENHANCE", systemImage: "slider.horizontal.3")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Processing mode").font(.headline)
                Picker("Processing mode", selection: $useAI) {
                    Text("AI Upscale 2×").tag(true)
                    Text("Classic").tag(false)
                }
                .pickerStyle(.segmented)
                if useAI {
                    Text("PiperSR generates each enlarged frame using a trained neural network. Install the model above before exporting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Resolution", selection: $multiplier) {
                        Text("1×").tag(1)
                        Text("2×").tag(2)
                        Text("4×").tag(4)
                    }
                    .pickerStyle(.segmented)
                    Text("Classic mode uses fast Lanczos scaling, not an AI model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            sliderRow(
                title: "Sharpen",
                value: $sharpness,
                range: 0...1,
                description: "Increase edge detail. Very high values may create halos."
            )
            sliderRow(
                title: "Reduce noise",
                value: $noiseReduction,
                range: 0...0.10,
                description: "Smooth compression grain before upscaling. Too much can blur textures."
            )
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .disabled(model.isProcessing)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(value.wrappedValue / range.upperBound * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("EXPORT", systemImage: "square.and.arrow.up")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if model.isProcessing {
                ProgressView(value: model.progress)
                Text("Processing \(Int(model.progress * 100))% • Keep the app open")
                    .font(.subheadline.monospacedDigit())
                Button(role: .destructive) { model.cancel() } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    model.enhance(factor: useAI ? 2 : multiplier,
                                  sharpness: sharpness,
                                  noise: noiseReduction,
                                  useAI: useAI)
                } label: {
                    Label(useAI ? "AI upscale 2× and export" : "Enhance and export", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.inputURL == nil || (useAI && !model.hasAIModel) || model.isInstallingAI)
            }
            if let outputURL = model.outputURL {
                ShareLink(item: outputURL, preview: SharePreview("Enhanced video")) {
                    Label("Save / Share enhanced video", systemImage: "square.and.arrow.up.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text("Tap Save to Files from the share sheet to keep a permanent copy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
