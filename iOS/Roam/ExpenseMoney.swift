import Foundation

enum ExpenseMoney {
    static let currencies = ["CNY", "JPY", "USD", "EUR", "GBP", "HKD", "KRW", "SGD", "AUD", "CAD", "THB"]
    static func parse(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]{1,10}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func format(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return currency + " " + (formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00")
    }
}
