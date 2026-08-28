import Foundation

public enum LineEnding: String, CaseIterable, Identifiable, Sendable {
    case lf = "LF"
    case crlf = "CRLF"
    case cr = "CR"

    public var id: String { rawValue }

    public var sequence: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    public static func detect(in text: String) -> LineEnding {
        if text.contains("\r\n") { return .crlf }
        if text.contains("\r") { return .cr }
        return .lf
    }

    public func normalize(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "\r", with: "\n")
        if self == .lf { return out }
        return out.replacingOccurrences(of: "\n", with: sequence)
    }
}
