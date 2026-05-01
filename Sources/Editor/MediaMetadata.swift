import Foundation
import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Lightweight metadata records for the non-text media kinds. Loaders
/// touch disk and (in the video case) hit AVFoundation, so they're all
/// async — the corresponding pill views run them in `.task` modifiers
/// so a heavy file doesn't block the main thread.

struct ImageMetadata: Equatable {
    var pixelSize: CGSize?
    var format: String?
    var fileSize: Int64?
    var bitDepth: Int?
    var colorModel: String?
    var hasAlpha: Bool?
}

struct VideoMetadata: Equatable {
    var resolution: CGSize?
    var durationSeconds: Double?
    var frameRate: Float?
    var codec: String?
    var fileSize: Int64?
}

struct BinaryMetadata: Equatable {
    var fileSize: Int64
    var typeDescription: String?
    var magicHeader: String?
}

struct PDFMetadata: Equatable {
    var pageCount: Int?
    var pageSize: CGSize?
    var fileSize: Int64?
}

enum MediaMetadataLoader {
    static func image(at url: URL) async -> ImageMetadata {
        await Task.detached(priority: .utility) {
            var meta = ImageMetadata()
            meta.fileSize = fileSize(at: url)
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            else { return meta }

            if let w = props[kCGImagePropertyPixelWidth] as? Int,
               let h = props[kCGImagePropertyPixelHeight] as? Int {
                meta.pixelSize = CGSize(width: w, height: h)
            }
            if let depth = props[kCGImagePropertyDepth] as? Int {
                meta.bitDepth = depth
            }
            if let model = props[kCGImagePropertyColorModel] as? String {
                meta.colorModel = model
            }
            if let alpha = props[kCGImagePropertyHasAlpha] as? Bool {
                meta.hasAlpha = alpha
            }
            if let typeID = CGImageSourceGetType(src) {
                let type = UTType(typeID as String)
                meta.format = type?.preferredFilenameExtension?.uppercased()
                    ?? type?.localizedDescription
                    ?? (typeID as String)
            }
            return meta
        }.value
    }

    static func video(at url: URL) async -> VideoMetadata {
        var meta = VideoMetadata()
        meta.fileSize = fileSize(at: url)

        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 { meta.durationSeconds = seconds }
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize) {
                meta.resolution = size
            }
            if let fps = try? await track.load(.nominalFrameRate), fps > 0 {
                meta.frameRate = fps
            }
            if let formats = try? await track.load(.formatDescriptions) {
                if let first = formats.first {
                    let fourCC = CMFormatDescriptionGetMediaSubType(first)
                    meta.codec = fourCharString(fourCC)
                }
            }
        }
        return meta
    }

    static func pdf(at url: URL) async -> PDFMetadata {
        await Task.detached(priority: .utility) {
            var meta = PDFMetadata()
            meta.fileSize = fileSize(at: url)
            if let doc = PDFDocument(url: url) {
                meta.pageCount = doc.pageCount
                if let firstPage = doc.page(at: 0) {
                    meta.pageSize = firstPage.bounds(for: .mediaBox).size
                }
            }
            return meta
        }.value
    }

    static func binary(at url: URL) async -> BinaryMetadata {
        await Task.detached(priority: .utility) {
            let size = fileSize(at: url) ?? 0
            var meta = BinaryMetadata(fileSize: size)

            // First few bytes — useful for magic-byte sniffing and just
            // for "what is this file" feedback in the pill.
            if let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                let bytes = handle.readData(ofLength: 8)
                if !bytes.isEmpty {
                    meta.magicHeader = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                }
            }

            // UTI-based type description: prefers the system's
            // localized name, then falls back to the extension or
            // "binary" for entirely unknown content.
            let ext = url.pathExtension
            if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
                meta.typeDescription = type.localizedDescription ?? ext.uppercased()
            } else {
                meta.typeDescription = "Binary"
            }
            return meta
        }.value
    }

    // MARK: - Helpers

    static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Decode a `FourCharCode` into the four-letter codec mnemonic
    /// (e.g. `avc1`, `hvc1`). Falls back to a hex representation for
    /// non-ASCII codes.
    private static func fourCharString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) {
            return String(bytes: bytes, encoding: .ascii) ?? String(format: "%08x", code)
        }
        return String(format: "%08x", code)
    }
}
