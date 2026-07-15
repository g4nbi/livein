import Foundation
import AuthenticationServices

// NOTE: YouTube OAuth membutuhkan GoogleClientID di Info.plist.
// Tambahkan key "GoogleClientID" ke Info.plist (via project.yml info.properties)
// untuk mengaktifkan OAuth. Tanpa itu, app masuk mode demo otomatis.
// Lihat Secrets.example.swift untuk cara konfigurasi.

enum YouTubeAuthState {
    case notConnected
    case connecting
    case connected(channelName: String)
    case demo

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .notConnected: return "Belum terhubung"
        case .connecting: return "Menghubungkan..."
        case .connected(let name): return "Terhubung: \(name)"
        case .demo: return "Mode Demo"
        }
    }
}

struct YouTubeLiveBroadcast: Codable {
    let id: String
    let title: String
    let streamKey: String?
    let rtmpsURL: String?
}

@MainActor
final class YouTubeAuthService: NSObject, ObservableObject {
    @Published private(set) var authState: YouTubeAuthState = .notConnected
    @Published private(set) var liveBroadcasts: [YouTubeLiveBroadcast] = []

    private var accessToken: String?
    private var webAuthSession: ASWebAuthenticationSession?

    private let oauthScope = "https://www.googleapis.com/auth/youtube"
    private let redirectScheme = "com.g4nbi.livein"

    // MARK: - Public

    func connectYouTube(presentingWindow: UIWindow?) {
        guard
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
            !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            // Google Client ID belum dikonfigurasi — aktifkan mode demo
            authState = .demo
            return
        }

        guard let authURL = buildAuthURL(clientID: clientID) else {
            authState = .notConnected
            return
        }

        authState = .connecting

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.authState = .notConnected
                    return
                }
                guard let url = callbackURL,
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.authState = .notConnected
                    return
                }
                await self.exchangeCodeForToken(code: code, clientID: clientID)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    func disconnect() {
        accessToken = nil
        liveBroadcasts = []
        authState = .notConnected
    }

    func enableDemoMode() {
        authState = .demo
        liveBroadcasts = [
            YouTubeLiveBroadcast(id: "demo-1", title: "Live Stream Demo", streamKey: nil, rtmpsURL: nil)
        ]
    }

    func fetchLiveBroadcasts() async {
        guard let token = accessToken else { return }
        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,contentDetails,status&broadcastStatus=upcoming&broadcastType=all") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return }

        liveBroadcasts = items.compactMap { item -> YouTubeLiveBroadcast? in
            guard let id = item["id"] as? String,
                  let snippet = item["snippet"] as? [String: Any],
                  let title = snippet["title"] as? String else { return nil }
            return YouTubeLiveBroadcast(id: id, title: title, streamKey: nil, rtmpsURL: nil)
        }
    }

    // MARK: - Private

    private func buildAuthURL(clientID: String) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "\(redirectScheme):/oauth2redirect"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: oauthScope),
            URLQueryItem(name: "access_type", value: "offline"),
        ]
        return components?.url
    }

    private func exchangeCodeForToken(code: String, clientID: String) async {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": "\(redirectScheme):/oauth2redirect",
            "grant_type": "authorization_code"
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            authState = .notConnected
            return
        }

        accessToken = token
        authState = .connected(channelName: "YouTube")
        await fetchLiveBroadcasts()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension YouTubeAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        DispatchQueue.main.sync {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first ?? UIWindow()
        }
    }
}
