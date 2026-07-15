import SwiftUI

struct SaweriaView: View {
    @ObservedObject var saweriaViewModel: SaweriaViewModel

    var body: some View {
        NavigationStack {
            List {
                // Connection status
                Section("Status Koneksi") {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(saweriaViewModel.connectionState.label)
                            .foregroundColor(.white)
                        Spacer()
                    }
                }

                // Demo mode notice
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mode Demo Aktif", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.orange)

                        Text("Saweria WebSocket backend belum tersedia. Gunakan tombol Test Alert untuk simulasi donasi di studio.")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.6))
                    }
                }

                // Test alert
                Section("Demo") {
                    Button {
                        saweriaViewModel.sendTestAlert()
                    } label: {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.white)
                            Text("Test Alert")
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Queue status
                if !saweriaViewModel.alertQueue.isEmpty {
                    Section("Antrian Alert") {
                        ForEach(saweriaViewModel.alertQueue) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.donorName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text(item.formattedAmount)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                Spacer()
                                if !item.message.isEmpty {
                                    Text(item.message)
                                        .font(.caption)
                                        .foregroundColor(Color(white: 0.5))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                // Future integration notice
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Integrasi Saweria Real")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(white: 0.7))

                        Text("Untuk menerima alert Saweria asli, diperlukan backend WebSocket yang meneruskan event dari Saweria ke aplikasi ini. Saweria asli TIDAK aktif dalam versi ini.")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.45))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Saweria")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusColor: Color {
        switch saweriaViewModel.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .demo: return .orange
        case .disconnected: return .gray
        }
    }
}
