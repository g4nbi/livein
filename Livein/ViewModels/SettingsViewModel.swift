import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: StreamSettings = StreamSettings.load()
    @Published var streamKey: String = KeychainService.streamKey

    let youTubeAuthService: YouTubeAuthService
    let thermalMonitor: ThermalMonitor

    init(youTubeAuthService: YouTubeAuthService, thermalMonitor: ThermalMonitor) {
        self.youTubeAuthService = youTubeAuthService
        self.thermalMonitor = thermalMonitor
    }

    func save() {
        settings.save()
        KeychainService.streamKey = streamKey
    }

    func clearStreamKey() {
        streamKey = ""
        KeychainService.delete(key: KeychainService.streamKeyAccount)
    }

    var bitrateStep: Double { 0.5 }
    var bitrateRange: ClosedRange<Double> { 2.0...10.0 }
}
