import Foundation

enum StreamStatus {
    case idle
    case connecting
    case live
    case reconnecting
    case error(String)

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: return "READY"
        case .connecting: return "CONNECTING"
        case .live: return "LIVE"
        case .reconnecting: return "RECONNECTING"
        case .error: return "ERROR"
        }
    }
}

struct StreamStats {
    var uploadKbps: Double = 0
    var droppedFrames: Int = 0
    var duration: TimeInterval = 0
    var totalBytesSent: Int64 = 0

    var durationFormatted: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        let s = Int(duration) % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
