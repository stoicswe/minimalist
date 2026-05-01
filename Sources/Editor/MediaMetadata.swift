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

struct AudioMetadata: Equatable {
    var durationSeconds: Double?
    var sampleRate: Double?
    var channelCount: Int?
    var codec: String?
    var bitRateKbps: Int?
    var fileSize: Int64?
    var title: String?
    var artist: String?
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

    static func audio(at url: URL) async -> AudioMetadata {
        var meta = AudioMetadata()
        meta.fileSize = fileSize(at: url)

        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 { meta.durationSeconds = seconds }
        }
        if let track = try? await asset.loadTracks(withMediaType: .audio).first {
            if let formats = try? await track.load(.formatDescriptions),
               let first = formats.first {
                let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee
                if let basic {
                    if basic.mSampleRate > 0 { meta.sampleRate = basic.mSampleRate }
                    if basic.mChannelsPerFrame > 0 {
                        meta.channelCount = Int(basic.mChannelsPerFrame)
                    }
                }
                let fourCC = CMFormatDescriptionGetMediaSubType(first)
                meta.codec = audioCodecLabel(fourCC)
            }
            if let bitsPerSecond = try? await track.load(.estimatedDataRate),
               bitsPerSecond > 0 {
                meta.bitRateKbps = Int((Double(bitsPerSecond) / 1000.0).rounded())
            }
        }

        // Best-effort common metadata pull — title / artist for the
        // pill. ID3v2, iTunes-style atoms, and Vorbis comments all map
        // through `commonMetadata`.
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle, meta.title == nil {
                    meta.title = try? await item.load(.stringValue)
                } else if key == .commonKeyArtist, meta.artist == nil {
                    meta.artist = try? await item.load(.stringValue)
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

    /// Map a CoreAudio `FourCharCode` to a friendly label — most
    /// formats use printable four-letter codes, but the integer-PCM
    /// variants come through as opaque numeric IDs that need a manual
    /// lookup.
    private static func audioCodecLabel(_ code: FourCharCode) -> String {
        switch code {
        case kAudioFormatLinearPCM:    return "PCM"
        case kAudioFormatMPEG4AAC:     return "AAC"
        case kAudioFormatMPEGLayer3:   return "MP3"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatFLAC:         return "FLAC"
        case kAudioFormatOpus:         return "Opus"
        case kAudioFormatAC3:          return "AC-3"
        case kAudioFormatMPEGD_USAC:   return "xHE-AAC"
        default:
            let label = fourCharString(code)
            return label.uppercased()
        }
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
