import Foundation

enum VideoResolution: String, CaseIterable, Codable {
    case hd720 = "720p"
    case hd1080 = "1080p"

    var width: Int32 {
        switch self {
        case .hd720: return 1280
        case .hd1080: return 1920
        }
    }

    var height: Int32 {
        switch self {
        case .hd720: return 720
        case .hd1080: return 1080
        }
    }

    var batteryWarning: Bool { self == .hd1080 }
}

enum FrameRate: Int, CaseIterable, Codable {
    case fps30 = 30
    case fps60 = 60

    var batteryWarning: Bool { self == .fps60 }
}

struct StreamSettings: Codable {
    var title: String = ""
    var rtmpsURL: String = "rtmps://a.rtmps.youtube.com/live2"
    var resolution: VideoResolution = .hd720
    var frameRate: FrameRate = .fps30
    var bitrateMbps: Double = 3.5
    var autoReconnect: Bool = true

    var bitrateKbps: Int { Int(bitrateMbps * 1000) }

    static let storageKey = "com.g4nbi.livein.streamSettings"

    static func load() -> StreamSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(StreamSettings.self, from: data) else {
            return StreamSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: StreamSettings.storageKey)
        }
    }
}
