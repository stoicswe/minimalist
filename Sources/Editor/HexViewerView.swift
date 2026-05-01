import SwiftUI

/// Read-only hex dump for files we can't display any other way. Three
/// columns: 8-digit hex offset, 16 bytes of hex, and an ASCII gutter
/// where non-printable bytes show as `.`. Loads up to a soft cap so
/// opening a multi-gigabyte binary doesn't lock the UI.
struct HexViewerView: View {
    let url: URL

    /// 4 MB is plenty to inspect a header / poke at small binaries
    /// without spending forever rendering. Anything past that is
    /// truncated with a footer note.
    private static let byteCeiling: Int = 4 * 1024 * 1024
    private static let bytesPerRow: Int = 16

    @State private var rows: [HexRow] = []
    @State private var truncated: Bool = false
    @State private var totalSize: Int64 = 0

    var body: some View {
        ScrollView([.vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HexRowView(row: row)
                }
                if truncated {
                    Text("Showing first \(Self.formatBytes(Int64(Self.byteCeiling))) of \(Self.formatBytes(totalSize)).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .textSelection(.enabled)
        .onAppear { load() }
        .onChange(of: url) { _, _ in load() }
    }

    private func load() {
        rows = []
        truncated = false
        totalSize = 0
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        totalSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        let limit = Self.byteCeiling
        let data = handle.readData(ofLength: limit)
        truncated = totalSize > Int64(limit)

        var built: [HexRow] = []
        built.reserveCapacity(data.count / Self.bytesPerRow + 1)
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let end = min(offset + Self.bytesPerRow, bytes.count)
            let slice = Array(bytes[offset..<end])
            built.append(HexRow(
                id: offset,
                offsetText: String(format: "%08X", offset),
                hexText: hexString(for: slice),
                asciiText: asciiString(for: slice)
            ))
            offset = end
        }
        rows = built
    }

    private func hexString(for bytes: [UInt8]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(Self.bytesPerRow)
        for i in 0..<Self.bytesPerRow {
            if i < bytes.count {
                parts.append(String(format: "%02x", bytes[i]))
            } else {
                parts.append("  ")
            }
            if i == 7 { parts.append("") } // visual gap halfway through the row
        }
        return parts.joined(separator: " ")
    }

    private func asciiString(for bytes: [UInt8]) -> String {
        var s = ""
        s.reserveCapacity(bytes.count)
        for b in bytes {
            if b >= 0x20 && b < 0x7f {
                s.append(Character(Unicode.Scalar(b)))
            } else {
                s.append(".")
            }
        }
        return s
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f.string(fromByteCount: bytes)
    }
}

private struct HexRow: Identifiable {
    let id: Int
    let offsetText: String
    let hexText: String
    let asciiText: String
}

private struct HexRowView: View {
    let row: HexRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(row.offsetText)
                .foregroundStyle(.tertiary)
            Text(row.hexText)
                .foregroundStyle(.primary)
            Text(row.asciiText)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
    }
}
