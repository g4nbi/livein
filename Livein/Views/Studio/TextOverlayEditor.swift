import SwiftUI

struct TextOverlayEditor: View {
    @Binding var overlay: TextOverlay
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Teks Overlay")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $overlay.isEnabled)
                    .labelsHidden()
                    .tint(.red)
            }

            TextField("Isi teks...", text: $overlay.text)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Ukuran: \(Int(overlay.fontSize))pt")
                    .font(.caption)
                    .foregroundColor(.gray)
                Slider(value: $overlay.fontSize, in: 12...72, step: 1)
                    .tint(.white)
            }

            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Hapus", systemImage: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(12)
    }
}
