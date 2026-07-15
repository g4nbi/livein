import SwiftUI

struct AlertOverlayView: View {
    let alert: AlertItem
    var onDismiss: () -> Void

    @State private var opacity: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 3)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.donorName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    Text(alert.formattedAmount)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.red)
                }

                Spacer()
            }

            if !alert.message.isEmpty {
                Text(alert.message)
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.85))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.75))
        )
        .padding(.horizontal, 16)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { opacity = 1 }
        }
        .onTapGesture { onDismiss() }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 80)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
