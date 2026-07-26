import Foundation

enum ExportFilename {
    static func baseName(date: Date, location: String?, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd-MM-yy"

        return [formatter.string(from: date), safePart(location ?? "UnknownLocation"), ""]
            .joined(separator: "_")
    }

    private static func safePart(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let words = value.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return words.isEmpty ? "Unknown" : words.joined(separator: "-")
    }
}
