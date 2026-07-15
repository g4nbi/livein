import SwiftUI

struct StreamView: View {
    @ObservedObject var streamViewModel: StreamViewModel

    var body: some View {
        NavigationStack {
            List {
                // Stream title
                Section("Judul Stream") {
                    TextField("Judul stream kamu...", text: $streamViewModel.settings.title)
                        .foregroundColor(.white)
                }

                // RTMPS URL
                Section("RTMPS URL") {
                    TextField("rtmps://...", text: $streamViewModel.settings.rtmpsURL)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }

                // Stream key
                Section {
                    SecureField("Stream Key", text: $streamViewModel.streamKey)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                } header: {
                    Text("Stream Key")
                } footer: {
                    Text("Disimpan secara aman di Keychain perangkat.")
                }

                // Quality
                Section("Kualitas Video") {
                    Picker("Resolusi", selection: $streamViewModel.settings.resolution) {
                        ForEach(VideoResolution.allCases, id: \.self) { res in
                            Text(res.rawValue)
                                .tag(res)
                        }
                    }

                    if streamViewModel.settings.resolution.batteryWarning {
                        Label("1080p lebih boros baterai", systemImage: "battery.50")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Picker("Frame Rate", selection: $streamViewModel.settings.frameRate) {
                        ForEach(FrameRate.allCases, id: \.self) { fps in
                            Text("\(fps.rawValue) FPS")
                                .tag(fps)
                        }
                    }

                    if streamViewModel.settings.frameRate.batteryWarning {
                        Label("60 FPS lebih boros baterai", systemImage: "battery.50")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // Bitrate
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Bitrate")
                            Spacer()
                            Text("\(String(format: "%.1f", streamViewModel.settings.bitrateMbps)) Mbps")
                                .foregroundColor(.gray)
                        }
                        Slider(
                            value: $streamViewModel.settings.bitrateMbps,
                            in: 2.0...10.0,
                            step: 0.5
                        )
                        .tint(.red)
                    }
                } footer: {
                    Text("Default: 3.5 Mbps. Disarankan 2–6 Mbps untuk koneksi stabil.")
                }

                // Reconnect
                Section {
                    Toggle("Auto Reconnect", isOn: $streamViewModel.settings.autoReconnect)
                        .tint(.red)
                } footer: {
                    Text("Koneksi ulang otomatis dengan exponential backoff jika stream terputus.")
                }

                // Save button
                Section {
                    Button {
                        streamViewModel.saveSettings()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Simpan Pengaturan")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.red)
                }
            }
            .navigationTitle("Stream")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
