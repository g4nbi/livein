import Foundation
import Combine

final class ThermalMonitor: ObservableObject {
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var isLowPowerMode: Bool = false
    @Published var shouldSuggestDowngrade: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        thermalState = ProcessInfo.processInfo.thermalState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateThermalState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .store(in: &cancellables)
    }

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        shouldSuggestDowngrade = thermalState >= .serious
    }

    var thermalLabel: String {
        switch thermalState {
        case .nominal: return "Normal"
        case .fair: return "Hangat"
        case .serious: return "Panas"
        case .critical: return "Kritis"
        @unknown default: return "Tidak diketahui"
        }
    }

    var thermalWarning: String? {
        switch thermalState {
        case .serious:
            return "Perangkat mulai panas. Disarankan turun ke 720p 30FPS untuk menghemat baterai."
        case .critical:
            return "Perangkat sangat panas! Segera turun ke 720p 30FPS atau akhiri streaming."
        default:
            return isLowPowerMode ? "Mode Hemat Daya aktif. Pertimbangkan 720p 30FPS." : nil
        }
    }
}
