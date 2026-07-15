import AVFoundation
import Combine
import SwiftUI

@MainActor
final class StudioViewModel: ObservableObject {
    @Published var isMuted: Bool = false
    @Published var currentPosition: AVCaptureDevice.Position = .back
    @Published var permissionsGranted: Bool = false
    @Published var permissionsDenied: Bool = false
    @Published var textOverlays: [TextOverlay] = TextOverlay.loadAll()

    private let cameraService: CameraService

    init(cameraService: CameraService) {
        self.cameraService = cameraService
    }

    func requestPermissions() async {
        let granted = await cameraService.requestPermissions()
        permissionsGranted = granted
        permissionsDenied = !granted
    }

    func startCamera(settings: StreamSettings) {
        cameraService.configure(resolution: settings.resolution, frameRate: settings.frameRate)
        cameraService.start()
    }

    func stopCamera() {
        cameraService.stop()
    }

    func flipCamera(settings: StreamSettings) {
        cameraService.flipCamera(resolution: settings.resolution, frameRate: settings.frameRate)
        currentPosition = cameraService.currentPosition
    }

    func toggleMute() {
        isMuted.toggle()
        cameraService.isMuted = isMuted
    }

    var captureSession: AVCaptureSession { cameraService.session }

    // MARK: - Text Overlays

    func addOverlay() {
        let overlay = TextOverlay()
        textOverlays.append(overlay)
        TextOverlay.saveAll(textOverlays)
    }

    func updateOverlay(_ overlay: TextOverlay) {
        if let index = textOverlays.firstIndex(where: { $0.id == overlay.id }) {
            textOverlays[index] = overlay
            TextOverlay.saveAll(textOverlays)
        }
    }

    func removeOverlay(id: UUID) {
        textOverlays.removeAll { $0.id == id }
        TextOverlay.saveAll(textOverlays)
    }
}
