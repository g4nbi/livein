import SwiftUI

struct TextOverlayView: View {
    let overlay: TextOverlay
    let containerSize: CGSize
    var onDragEnd: ((CGPoint) -> Void)?

    @State private var position: CGPoint

    init(overlay: TextOverlay, containerSize: CGSize, onDragEnd: ((CGPoint) -> Void)? = nil) {
        self.overlay = overlay
        self.containerSize = containerSize
        self.onDragEnd = onDragEnd
        _position = State(initialValue: CGPoint(
            x: overlay.positionX * containerSize.width,
            y: overlay.positionY * containerSize.height
        ))
    }

    var body: some View {
        Text(overlay.text)
            .font(.system(size: overlay.fontSize, weight: .semibold))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.3))
            .cornerRadius(4)
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        position = value.location
                    }
                    .onEnded { value in
                        let newX = min(max(value.location.x / containerSize.width, 0), 1)
                        let newY = min(max(value.location.y / containerSize.height, 0), 1)
                        onDragEnd?(CGPoint(x: newX, y: newY))
                    }
            )
            .opacity(overlay.isEnabled ? 1 : 0)
    }
}
