import Foundation
import Combine
import CoreMedia

@MainActor
final class StreamViewModel: ObservableObject {
    @Published private(set) var status: StreamStatus = .idle
    @Published private(set) var stats: StreamStats = StreamStats()
    @Published var settings: StreamSettings = StreamSettings.load()
    @Published var streamKey: String = KeychainService.streamKey

    private let cameraService: CameraService
    private let streamService: RTMPStreamService
    private var videoEncoder: VideoEncoder?
    private var audioEncoder: AudioEncoder?

    private let encoderQueue = DispatchQueue(label: "com.g4nbi.livein.encoder", qos: .userInitiated)

    init(cameraService: CameraService) {
        self.cameraService = cameraService
        self.streamService = RTMPStreamService()
        streamService.delegate = self
        setupCameraCallbacks()
    }

    private func setupCameraCallbacks() {
        cameraService.onVideoSampleBuffer = { [weak self] buffer in
            self?.encoderQueue.async { self?.videoEncoder?.encode(sampleBuffer: buffer) }
        }
        cameraService.onAudioSampleBuffer = { [weak self] buffer in
            self?.encoderQueue.async { self?.audioEncoder?.encode(sampleBuffer: buffer) }
        }
    }

    // MARK: - Controls

    func goLive() {
        guard !status.isLive else { return }
        saveStreamKey()

        let bps = Int(settings.bitrateMbps * 1_000_000)
        let venc = VideoEncoder(
            width: settings.resolution.width,
            height: settings.resolution.height,
            frameRate: settings.frameRate.rawValue,
            bitrateBps: bps
        )
        venc.delegate = self
        venc.configure()
        videoEncoder = venc

        let aenc = AudioEncoder()
        aenc.delegate = self
        audioEncoder = aenc

        streamService.connect(
            rtmpsURL: settings.rtmpsURL,
            streamKey: streamKey,
            autoReconnect: settings.autoReconnect
        )
    }

    func endLive() {
        streamService.disconnect()
        videoEncoder?.invalidate()
        videoEncoder = nil
        audioEncoder?.invalidate()
        audioEncoder = nil
    }

    func saveSettings() {
        settings.save()
        saveStreamKey()
    }

    private func saveStreamKey() {
        KeychainService.streamKey = streamKey
    }
}

// MARK: - RTMPStreamServiceDelegate

extension StreamViewModel: RTMPStreamServiceDelegate {
    nonisolated func streamService(_ service: RTMPStreamService, didChangeStatus status: StreamStatus) {
        Task { @MainActor in self.status = status }
    }

    nonisolated func streamService(_ service: RTMPStreamService, didUpdateStats stats: StreamStats) {
        Task { @MainActor in self.stats = stats }
    }
}

// MARK: - VideoEncoderDelegate

extension StreamViewModel: VideoEncoderDelegate {
    nonisolated func encoder(_ encoder: VideoEncoder, didOutput sampleBuffer: CMSampleBuffer) {
        streamService.sendVideoBuffer(sampleBuffer)
    }
}

// MARK: - AudioEncoderDelegate

extension StreamViewModel: AudioEncoderDelegate {
    nonisolated func audioEncoder(_ encoder: AudioEncoder, didOutput data: Data, pts: CMTime) {
        streamService.sendAudioData(data, pts: pts)
    }
}
