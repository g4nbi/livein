# Livein

Aplikasi iOS native untuk livestream IRL (In Real Life) menggunakan RTMPS.

> **Dibuat dengan:** Swift, SwiftUI, AVFoundation, VideoToolbox — tanpa Flutter, React Native, atau dependency berat.

---

## Status Fitur

### ✅ Sudah Berfungsi
- **Studio Kamera** — Preview fullscreen dengan `AVCaptureVideoPreviewLayer`, flip kamera depan/belakang, mute/unmute mikrofon
- **Teks Overlay** — Tambah/edit/hapus teks, drag posisi, atur ukuran font, aktif/nonaktif, tersimpan otomatis
- **Stream Settings** — RTMPS URL, stream key (disimpan di Keychain), pilihan 720p/1080p, 30/60 FPS, bitrate 2–10 Mbps, auto reconnect
- **Encoding Hardware** — H.264 via VideoToolbox (hardware acceleration), audio AAC
- **Performa** — Camera session di background queue, tidak mengkonversi frame ke UIImage, stats update 1x/detik
- **Thermal Monitor** — Deteksi panas perangkat dan Mode Hemat Daya, saran turun ke 720p30
- **Alert Saweria (Demo)** — Tampilkan nama, nominal, pesan; queue alert; fade in/out; tombol Test Alert; durasi 5 detik
- **Tab UI** — Studio, Stream, Saweria, Pengaturan

### 🚧 Masih Demo / Belum Aktif
- **Streaming RTMPS** — Encoding berjalan, koneksi RTMPS diimplementasikan dengan Network.framework + TLS. **Perlu diuji dengan server RTMPS nyata.**
- **Alert Saweria Real** — Membutuhkan backend WebSocket yang meneruskan event dari Saweria. Saweria asli **TIDAK** aktif dalam versi ini.
- **YouTube OAuth** — Membutuhkan Google Client ID di `Secrets.swift`. YouTube Live **TIDAK** aktif tanpa OAuth.

---

## Cara Generate dan Jalankan Project

### Prasyarat

- macOS 14+ dengan Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Langkah

```bash
# Clone repository
git clone https://github.com/g4nbi/livein.git
cd livein/Livein

# Generate Xcode project
xcodegen generate --spec project.yml

# Buka di Xcode
open Livein.xcodeproj
```

Jalankan di simulator atau perangkat fisik iOS 17+ dari Xcode (⌘R).

> **Catatan:** Kamera hanya berfungsi di perangkat fisik, bukan simulator.

---

## Konfigurasi YouTube OAuth (Opsional)

1. Salin `Livein/Secrets.example.swift` menjadi `Livein/Secrets.swift`
2. Buat project di [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
3. Aktifkan YouTube Data API v3
4. Buat OAuth Client ID bertipe **iOS** dengan Bundle ID `com.g4nbi.livein`
5. Isi `googleClientID` di `Secrets.swift`

```swift
// Secrets.swift (JANGAN di-commit)
enum Secrets {
    static let googleClientID: String? = "YOUR_CLIENT_ID.apps.googleusercontent.com"
}
```

`Secrets.swift` sudah ada di `.gitignore` dan tidak akan ter-commit.

---

## Cara Upload ke GitHub

```bash
cd livein   # direktori root repository

git init
git add .
git commit -m "Initial commit: Livein iOS app"

# Buat repository di GitHub, lalu:
git remote add origin https://github.com/g4nbi/livein.git
git branch -M main
git push -u origin main
```

---

## Cara Menjalankan GitHub Actions

1. Push ke branch `main` — Actions otomatis berjalan
2. Atau trigger manual: GitHub → tab **Actions** → pilih **Build iOS (Unsigned IPA)** → **Run workflow**
3. Tunggu build selesai (sekitar 10–15 menit)

---

## Cara Download Unsigned IPA

1. Buka tab **Actions** di repository GitHub
2. Klik build yang berhasil
3. Scroll ke bagian **Artifacts**
4. Download **Livein-unsigned-ipa**

---

## Instalasi IPA

⚠️ **IPA ini belum ditandatangani.** Untuk menginstall di perangkat fisik, kamu perlu:

- **AltStore / SideStore** — Sign dengan Apple ID personal (gratis, batas 3 app)
- **Apple Developer Program** — Sign dengan Development/Distribution certificate
- **Sideloading tool** lainnya (AltSign, Sideloadly)

IPA tidak bisa diinstall langsung tanpa signing.

---

## Saweria Real

Untuk menerima alert Saweria asli, kamu perlu:

1. Backend server yang terhubung ke Saweria via WebSocket/webhook mereka
2. Backend tersebut meneruskan event donasi ke aplikasi Livein via WebSocket
3. Implementasikan URL WebSocket di `SaweriaWebSocketService.swift` → fungsi `connect(url:)`
4. Ubah `isDemoMode = false` di `SaweriaViewModel`

---

## Struktur Project

```
Livein/
├── project.yml                      # XcodeGen project spec
├── .github/workflows/build-ios.yml  # GitHub Actions CI
├── Livein/
│   ├── App/
│   │   └── LiveinApp.swift          # Entry point (@main)
│   ├── Models/                      # Data models
│   ├── Services/                    # Camera, RTMP, Saweria, YouTube, Keychain
│   ├── ViewModels/                  # MVVM ViewModels
│   ├── Views/                       # SwiftUI Views (Studio, Stream, Saweria, Settings)
│   ├── Assets.xcassets/
│   ├── Secrets.example.swift        # Template konfigurasi (aman di-commit)
│   └── Info.plist                   # Auto-generated oleh XcodeGen
├── .gitignore
├── LICENSE
└── README.md
```

---