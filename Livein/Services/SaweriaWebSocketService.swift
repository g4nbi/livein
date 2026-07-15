import Foundation
import Combine

// NOTE: Saweria WebSocket backend belum tersedia.
// Service ini menyiapkan struktur koneksi untuk integrasi Saweria di masa mendatang.
// Mode saat ini: DEMO ONLY

enum SaweriaConnectionState {
    case disconnected
    case connecting
    case connected
    case demo

    var label: String {
        switch self {
        case .disconnected: return "Tidak terhubung"
        case .connecting: return "Menghubungkan..."
        case .connected: return "Terhubung"
        case .demo: return "Mode Demo"
        }
    }
}

protocol SaweriaWebSocketServiceDelegate: AnyObject {
    func saweriaService(_ service: SaweriaWebSocketService, didReceiveAlert alert: AlertItem)
    func saweriaService(_ service: SaweriaWebSocketService, didChangeState state: SaweriaConnectionState)
}

final class SaweriaWebSocketService: NSObject {
    weak var delegate: SaweriaWebSocketServiceDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isDemoMode = true

    private var reconnectTimer: Timer?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5

    private(set) var state: SaweriaConnectionState = .disconnected {
        didSet {
            DispatchQueue.main.async { self.delegate?.saweriaService(self, didChangeState: self.state) }
        }
    }

    // MARK: - Public

    /// Koneksi ke backend Saweria WebSocket.
    /// Saat ini dalam mode demo karena backend belum tersedia.
    func connect(url: URL? = nil) {
        guard !isDemoMode else {
            state = .demo
            return
        }

        guard let url else {
            state = .disconnected
            return
        }

        state = .connecting
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        receive()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        state = .disconnected
    }

    func enableDemoMode() {
        isDemoMode = true
        disconnect()
        state = .demo
    }

    // MARK: - Demo

    func sendDemoAlert(_ alert: AlertItem? = nil) {
        let item = alert ?? AlertItem.randomDemo()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.saweriaService(self, didReceiveAlert: item)
        }
    }

    // MARK: - Private

    private func receive() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receive()
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["donorName"] as? String,
                  let amount = json["amount"] as? Int else { return }
            let msg = json["message"] as? String ?? ""
            let alert = AlertItem(donorName: name, amount: amount, message: msg)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.saweriaService(self, didReceiveAlert: alert)
            }
        case .data:
            break
        @unknown default:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempt < maxReconnectAttempts else {
            state = .disconnected
            return
        }
        let delay = min(pow(2.0, Double(reconnectAttempt)), 60.0)
        reconnectAttempt += 1
        state = .connecting

        DispatchQueue.main.async { [weak self] in
            self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                // Re-connect would need the URL stored; skipped here as demo mode is default
                self?.state = .disconnected
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SaweriaWebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        reconnectAttempt = 0
        state = .connected
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        scheduleReconnect()
    }
}
