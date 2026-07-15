import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var streamViewModel: StreamViewModel
    @State private var showStreamKeyWarning = false

    var body: some View {
        NavigationStack {
            List {
                // Thermal / Power
                thermalSection

                // YouTube
                youtubeSection

                // About
                aboutSection
            }
            .navigationTitle("Pengaturan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Thermal

    private var thermalSection: some View {
        Section {
            HStack {
                Label(settingsViewModel.thermalMonitor.thermalLabel, systemImage: thermalIcon)
                    .foregroundColor(thermalColor)
                Spacer()
                if settingsViewModel.thermalMonitor.isLowPowerMode {
                    Text("Hemat Daya")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                }
            }

            if let warning = settingsViewModel.thermalMonitor.thermalWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                if settingsViewModel.thermalMonitor.shouldSuggestDowngrade {
                    Button("Turun ke 720p 30FPS") {
                        streamViewModel.settings.resolution = .hd720
                        streamViewModel.settings.frameRate = .fps30
                        streamViewModel.saveSettings()
                    }
                    .foregroundColor(.orange)
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Status Perangkat")
        }
    }

    private var thermalIcon: String {
        switch settingsViewModel.thermalMonitor.thermalState {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "thermometer.sun.fill"
        @unknown default: return "thermometer"
        }
    }

    private var thermalColor: Color {
        switch settingsViewModel.thermalMonitor.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .white
        }
    }

    // MARK: - YouTube

    private var youtubeSection: some View {
        Section {
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("YouTube")
                        .foregroundColor(.white)
                    Text(settingsViewModel.youTubeAuthService.authState.label)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()

                switch settingsViewModel.youTubeAuthService.authState {
                case .notConnected:
                    Button("Hubungkan") {
                        settingsViewModel.youTubeAuthService.enableDemoMode()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                case .demo:
                    Text("Demo")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                case .connected:
                    Button("Putus") {
                        settingsViewModel.youTubeAuthService.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                case .connecting:
                    ProgressView()
                        .tint(.white)
                }
            }

            if case .demo = settingsViewModel.youTubeAuthService.authState {
                Text("YouTube OAuth membutuhkan Google Client ID di Secrets.swift. Lihat Secrets.example.swift untuk konfigurasi. Streaming YouTube TIDAK aktif dalam mode demo.")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.5))
            }
        } header: {
            Text("YouTube")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("Tentang") {
            LabeledContent("Versi", value: "1.0.0")
            LabeledContent("Bundle ID", value: "com.g4nbi.livein")

            Link(destination: URL(string: "https://github.com/g4nbi/livein")!) {
                HStack {
                    Text("GitHub Repository")
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}
