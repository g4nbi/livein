import SwiftUI

struct ContentView: View {
    @StateObject private var app = AppContainer()
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StudioView(
                studioViewModel: app.studioViewModel,
                streamViewModel: app.streamViewModel,
                saweriaViewModel: app.saweriaViewModel
            )
            .tabItem {
                Label("Studio", systemImage: "video.fill")
            }
            .tag(0)

            StreamView(streamViewModel: app.streamViewModel)
                .tabItem {
                    Label("Stream", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(1)

            SaweriaView(saweriaViewModel: app.saweriaViewModel)
                .tabItem {
                    Label("Saweria", systemImage: "gift.fill")
                }
                .tag(2)

            SettingsView(
                settingsViewModel: app.settingsViewModel,
                streamViewModel: app.streamViewModel
            )
            .tabItem {
                Label("Pengaturan", systemImage: "gearshape.fill")
            }
            .tag(3)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}
