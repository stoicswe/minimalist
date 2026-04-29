import Foundation

struct Indentation: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case tabs, spaces
        var id: String { rawValue }
        var label: String { self == .tabs ? "Tabs" : "Spaces" }
    }

    var kind: Kind
    var width: Int

    var unit: String {
        switch kind {
        case .tabs: return "\t"
        case .spaces: return String(repeating: " ", count: max(width, 1))
        }
    }

    static func detect(in text: String) -> Indentation? {
        var tabLines = 0
        var spaceCounts: [Int: Int] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let first = rawLine.first else { continue }
            if first == "\t" { tabLines += 1; continue }
            if first == " " {
                var n = 0
                for ch in rawLine {
                    if ch == " " { n += 1 } else { break }
                }
                if n > 0 { spaceCounts[n, default: 0] += 1 }
            }
        }
        let totalSpaceLines = spaceCounts.values.reduce(0, +)
        if tabLines == 0 && totalSpaceLines == 0 { return nil }
        if tabLines >= totalSpaceLines { return Indentation(kind: .tabs, width: 4) }
        let widths = spaceCounts.keys.sorted()
        for candidate in [2, 4, 8] where widths.contains(candidate) {
            return Indentation(kind: .spaces, width: candidate)
        }
        return Indentation(kind: .spaces, width: widths.first ?? 4)
    }

    static func defaultsFromUserPrefs() -> Indentation {
        let kindRaw = UserDefaults.standard.string(forKey: "default.indent.kind") ?? Kind.spaces.rawValue
        let width = UserDefaults.standard.object(forKey: "default.indent.width") as? Int ?? 4
        return Indentation(kind: Kind(rawValue: kindRaw) ?? .spaces, width: width)
    }

    func reformat(text: String, from old: Indentation) -> String {
        let lines = text.components(separatedBy: "\n")
        let oldUnitWidth: Int = (old.kind == .tabs) ? 1 : max(old.width, 1)
        let result = lines.map { line -> String in
            var prefixCount = 0
            var visualColumns = 0
            for ch in line {
                if ch == "\t" {
                    visualColumns += oldUnitWidth
                    prefixCount += 1
                } else if ch == " " {
                    visualColumns += 1
                    prefixCount += 1
                } else { break }
            }
            let levels = visualColumns / oldUnitWidth
            let body = String(line.dropFirst(prefixCount))
            return String(repeating: unit, count: levels) + body
        }
        return result.joined(separator: "\n")
    }
}
