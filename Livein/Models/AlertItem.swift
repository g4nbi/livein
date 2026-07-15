import Foundation

struct AlertItem: Identifiable {
    let id: UUID = UUID()
    let donorName: String
    let amount: Int
    let message: String
    let createdAt: Date = Date()

    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "Rp \(amount)"
    }
}

extension AlertItem {
    static let demo = AlertItem(
        donorName: "Penonton Setia",
        amount: 50000,
        message: "Semangat streamin! Kontennya bagus banget 🔥"
    )

    static func randomDemo() -> AlertItem {
        let names = ["BangJoko", "SitiCantik", "Gamer99", "PenggemarBerat", "AnonDonor"]
        let amounts = [5000, 10000, 20000, 50000, 100000]
        let messages = [
            "GG! Keep it up!",
            "Mantap jiwa!",
            "Semangat!",
            "Konten favoritku 🙌",
            ""
        ]
        return AlertItem(
            donorName: names.randomElement()!,
            amount: amounts.randomElement()!,
            message: messages.randomElement()!
        )
    }
}
