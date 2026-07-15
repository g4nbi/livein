import Foundation
import CoreGraphics

struct TextOverlay: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String = "Livein"
    var fontSize: CGFloat = 24
    var positionX: CGFloat = 0.5
    var positionY: CGFloat = 0.9
    var isEnabled: Bool = true

    static let storageKey = "com.g4nbi.livein.textOverlays"

    static func loadAll() -> [TextOverlay] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let overlays = try? JSONDecoder().decode([TextOverlay].self, from: data) else {
            return []
        }
        return overlays
    }

    static func saveAll(_ overlays: [TextOverlay]) {
        if let data = try? JSONEncoder().encode(overlays) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
