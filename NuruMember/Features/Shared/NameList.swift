// One way to name a few people (the iOS walk's E18; Android's A4): "Ada",
// "Ada and Ben", "Ada, Ben and Cara" — and with more than are named,
// "Ada, Ben, Cara and 2 others". The presence and footprints lines each
// joined their own way and doubled the "and" ("Dee, Cara and Builder and 2
// others"). Pure, so the tests pin it.
import Foundation

enum NameList {
    /// `stable`: alphabetical, so a line doesn't reshuffle its names on every
    /// load (the server's order is "most recent first").
    static func join(_ names: [String], others: Int, stable: Bool = false) -> String? {
        var named = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if stable { named.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
        var items = named
        if others > 0 { items.append("\(others) other\(others == 1 ? "" : "s")") }
        guard let last = items.last else { return nil }
        if items.count == 1 { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
