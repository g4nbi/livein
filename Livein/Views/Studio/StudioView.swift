import SwiftUI
import AVFoundation

struct StudioView: View {
    @ObservedObject var studioViewModel: StudioViewModel
    @ObservedObject var streamViewModel: StreamViewModel
    @ObservedObject var saweriaViewModel: SaweriaViewModel

    @State private var showOverlayEditor = false
    @State private var permissionsRequested = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if studioViewModel.permissionsGranted {
                cameraLayer
            } else if studioViewModel.permissionsDenied {
                permissionDeniedView
            } else {
                permissionRequestView
            }
        }
        .task {
            guard !permissionsRequested else { return }
            permissionsRequested = true
            await studioViewModel.requestPermissions()
            if studioViewModel.permissionsGranted {
                studioViewModel.startCamera(settings: streamViewModel.settings)
            }
        }
        .onDisappear {
            if !streamViewModel.status.isLive {
                studioViewModel.stopCamera()
            }
        }
    }

    // MARK: - Camera Layer

    private var cameraLayer: some View {
        GeometryReader { geo in
            ZStack {
                // Camera preview — no UIImage conversion, no @Published frame storage
                CameraPreviewView(session: studioViewModel.captureSession)
                    .ignoresSafeArea()

                // Text overlays (only enabled ones rendered)
                ForEach(studioViewModel.textOverlays.filter { $0.isEnabled }) { overlay in
                    TextOverlayView(
                        overlay: overlay,
                        containerSize: geo.size
                    ) { newPos in
                        var updated = overlay
                        updated.positionX = newPos.x
                        updated.positionY = newPos.y
                        studioViewModel.updateOverlay(updated)
                    }
                }

                // Saweria alert overlay
                if let alert = saweriaViewModel.currentAlert {
                    AlertOverlayView(alert: alert) {
                        saweriaViewModel.dismissCurrentAlert()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: saweriaViewModel.currentAlert?.id)
                }

                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            statusBadge

            Spacer()

            if streamViewModel.status.isLive {
                statsView
            }

            Button {
                showOverlayEditor.toggle()
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .sheet(isPresented: $showOverlayEditor) {
            overlayEditorSheet
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            if streamViewModel.status.isLive {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
            Text(streamViewModel.status.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(streamViewModel.status.isLive ? .white : Color(white: 0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(streamViewModel.status.isLive ? Color.red : Color.black.opacity(0.5))
        .cornerRadius(12)
    }

    private var statsView: some View {
        HStack(spacing: 12) {
            Text(streamViewModel.stats.durationFormatted)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)

            Text("\(Int(streamViewModel.stats.uploadKbps)) kbps")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(white: 0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if case .error(let msg) = streamViewModel.status {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 24) {
                controlButton(icon: "arrow.triangle.2.circlepath.camera.fill") {
                    studioViewModel.flipCamera(settings: streamViewModel.settings)
                }

                goLiveButton

                controlButton(
                    icon: studioViewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                    tint: studioViewModel.isMuted ? .red : .white
                ) {
                    studioViewModel.toggleMute()
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var goLiveButton: some View {
        Button {
            if streamViewModel.status.isLive {
                streamViewModel.endLive()
            } else {
                streamViewModel.goLive()
            }
        } label: {
            Text(streamViewModel.status.isLive ? "END" : "GO LIVE")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 88, height: 48)
                .background(streamViewModel.status.isLive ? Color(white: 0.2) : Color.red)
                .cornerRadius(24)
        }
        .disabled(streamViewModel.settings.rtmpsURL.isEmpty || streamViewModel.streamKey.isEmpty)
    }

    private func controlButton(icon: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
    }

    // MARK: - Overlay Editor Sheet

    private var overlayEditorSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($studioViewModel.textOverlays) { $overlay in
                        TextOverlayEditor(overlay: $overlay) {
                            studioViewModel.removeOverlay(id: overlay.id)
                        }
                    }

                    Button {
                        studioViewModel.addOverlay()
                    } label: {
                        Label("Tambah Teks", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle("Teks Overlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { showOverlayEditor = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Permission Views

    private var permissionRequestView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.5))
            Text("Izin Diperlukan")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
            Text("Livein membutuhkan akses kamera dan mikrofon untuk streaming.")
                .font(.body)
                .foregroundColor(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Izin Ditolak")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
            Text("Buka Pengaturan > Privasi > Kamera dan aktifkan akses untuk Livein.")
                .font(.body)
                .foregroundColor(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Buka Pengaturan") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }
}
