import Foundation

/// Holds the single shared camera service and all ViewModels derived from it.
/// Created once at app startup and shared via ContentView.
@MainActor
final class AppContainer: ObservableObject {
    let cameraService = CameraService()
    let thermalMonitor = ThermalMonitor()
    let youTubeAuthService = YouTubeAuthService()

    lazy var studioViewModel = StudioViewModel(cameraService: cameraService)
    lazy var streamViewModel = StreamViewModel(cameraService: cameraService)
    lazy var saweriaViewModel = SaweriaViewModel()
    lazy var settingsViewModel: SettingsViewModel = {
        SettingsViewModel(youTubeAuthService: youTubeAuthService, thermalMonitor: thermalMonitor)
    }()
}
