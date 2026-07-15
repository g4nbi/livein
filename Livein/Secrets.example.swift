// Secrets.example.swift
// Salin file ini menjadi Secrets.swift dan isi nilainya.
// File Secrets.swift sudah ada di .gitignore dan TIDAK akan ikut di-commit.

import Foundation

enum Secrets {
    /// Google OAuth Client ID untuk integrasi YouTube.
    /// Dapatkan dari Google Cloud Console:
    /// https://console.cloud.google.com/apis/credentials
    /// Pilih "iOS" sebagai application type dan gunakan Bundle ID: com.g4nbi.livein
    static let googleClientID: String? = nil // Ganti dengan Client ID kamu

    // Contoh:
    // static let googleClientID: String? = "123456789-abcdefghijk.apps.googleusercontent.com"
}
