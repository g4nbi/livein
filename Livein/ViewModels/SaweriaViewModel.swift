import Foundation
import Combine

@MainActor
final class SaweriaViewModel: ObservableObject {
    @Published private(set) var connectionState: SaweriaConnectionState = .demo
    @Published private(set) var alertQueue: [AlertItem] = []
    @Published private(set) var currentAlert: AlertItem? = nil

    private let webSocketService: SaweriaWebSocketService
    private var alertTimer: Timer?
    private let alertDuration: TimeInterval = 5.0

    init() {
        webSocketService = SaweriaWebSocketService()
        webSocketService.delegate = self
        webSocketService.enableDemoMode()
    }

    func sendTestAlert() {
        let alert = AlertItem.randomDemo()
        enqueue(alert)
    }

    private func enqueue(_ alert: AlertItem) {
        alertQueue.append(alert)
        if currentAlert == nil {
            showNextAlert()
        }
    }

    private func showNextAlert() {
        guard !alertQueue.isEmpty else {
            currentAlert = nil
            return
        }
        currentAlert = alertQueue.removeFirst()
        alertTimer?.invalidate()
        alertTimer = Timer.scheduledTimer(withTimeInterval: alertDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentAlert = nil
                self?.showNextAlert()
            }
        }
    }

    func dismissCurrentAlert() {
        alertTimer?.invalidate()
        currentAlert = nil
        showNextAlert()
    }
}

// MARK: - SaweriaWebSocketServiceDelegate

extension SaweriaViewModel: SaweriaWebSocketServiceDelegate {
    nonisolated func saweriaService(_ service: SaweriaWebSocketService, didReceiveAlert alert: AlertItem) {
        Task { @MainActor in self.enqueue(alert) }
    }

    nonisolated func saweriaService(_ service: SaweriaWebSocketService, didChangeState state: SaweriaConnectionState) {
        Task { @MainActor in self.connectionState = state }
    }
}
