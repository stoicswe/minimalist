import Foundation

/// Formats binary files for the hex viewer: `00000000  de ad be ef …  |ASCII|`.
/// Platform-neutral so both front ends render identical dumps — each app
/// only decides how to display the resulting monospaced text.
public enum HexDump {

    /// 4 MB is plenty to inspect a header or poke at a small binary
    /// without spending forever rendering. Past that the dump is
    /// truncated and `Result.truncated` is set.
    public static let byteCeiling = 4 * 1024 * 1024
    public static let bytesPerRow = 16

    public struct Result: Sendable {
        /// The formatted dump, one row per 16 bytes.
        public let text: String
        /// Whether the file is larger than `byteCeiling`.
        public let truncated: Bool
        /// The file's full size on disk, in bytes.
        public let totalSize: Int64
    }

    /// Read up to `byteCeiling` bytes from `url` and format them.
    public static func dump(url: URL, limit: Int = byteCeiling) -> Result {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let totalSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .init(text: "", truncated: false, totalSize: totalSize)
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: limit)
        return .init(
            text: format(data: data),
            truncated: totalSize > Int64(limit),
            totalSize: totalSize
        )
    }

    /// Format `data` as an offset / hex / ASCII table.
    public static func format(data: Data) -> String {
        let bytes = [UInt8](data)
        var lines: [String] = []
        lines.reserveCapacity(bytes.count / bytesPerRow + 1)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + bytesPerRow, bytes.count)
            let slice = Array(bytes[offset..<end])
            lines.append(
                String(format: "%08X", offset)
                    + "   " + hexColumn(slice)
                    + "   " + asciiColumn(slice)
            )
            offset = end
        }
        return lines.joined(separator: "\n")
    }

    /// A short summary line for the status pill: size plus the format
    /// guessed from the file's magic bytes.
    public static func summary(url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        var parts = [byteCount(size)]
        if let magic = magic(url: url) { parts.insert(magic, at: 0) }
        return parts.joined(separator: "  |  ")
    }

    /// Human-readable byte count, binary units (KiB steps, decimal-ish labels).
    public static func byteCount(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1_024, unit < units.count - 1 {
            value /= 1_024
            unit += 1
        }
        if unit == 0 { return "\(bytes) bytes" }
        return String(format: "%.1f %@", value, units[unit])
    }

    /// Identify a handful of common formats from their leading bytes.
    public static func magic(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = [UInt8](handle.readData(ofLength: 8))
        guard !head.isEmpty else { return nil }
        func starts(_ prefix: [UInt8]) -> Bool {
            head.count >= prefix.count && Array(head.prefix(prefix.count)) == prefix
        }
        if starts([0x7F, 0x45, 0x4C, 0x46]) { return "ELF" }
        if starts([0x4D, 0x5A]) { return "PE" }
        if starts([0xCA, 0xFE, 0xBA, 0xBE]) { return "Mach-O universal" }
        if starts([0xCF, 0xFA, 0xED, 0xFE]) { return "Mach-O" }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "ZIP" }
        if starts([0x1F, 0x8B]) { return "GZIP" }
        if starts([0x25, 0x50, 0x44, 0x46]) { return "PDF" }
        if starts([0x53, 0x51, 0x4C, 0x69]) { return "SQLite" }
        if starts([0x00, 0x61, 0x73, 0x6D]) { return "WebAssembly" }
        return nil
    }

    private static func hexColumn(_ bytes: [UInt8]) -> String {
        var parts: [String] = []
        for index in 0..<bytesPerRow {
            parts.append(index < bytes.count ? String(format: "%02x", bytes[index]) : "  ")
            // Visual gap halfway through the row.
            if index == 7 { parts.append("") }
        }
        return parts.joined(separator: " ")
    }

    private static func asciiColumn(_ bytes: [UInt8]) -> String {
        var text = ""
        text.reserveCapacity(bytes.count)
        for byte in bytes {
            text.append(byte >= 0x20 && byte < 0x7F ? Character(Unicode.Scalar(byte)) : ".")
        }
        return text
    }
}
