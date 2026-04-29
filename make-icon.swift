#!/usr/bin/env swift
//
// Generates the AppIcon.appiconset for Minimalist.
// Renders a zen enso (a single brushstroke circle, slightly open at the top-right)
// with a serif "m." in the center.
//
// Run from the repo root:
//   swift make-icon.swift
//

import AppKit
import CoreGraphics

let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"

let macSizes: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

func renderPNG(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext failed") }

    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    // Background — soft warm cream with a subtle vertical gradient.
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    bgPath.addClip()

    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.985, green: 0.975, blue: 0.945, alpha: 1.0),
        NSColor(calibratedRed: 0.945, green: 0.925, blue: 0.880, alpha: 1.0),
    ])!
    bgGradient.draw(in: rect, angle: -90)

    // Enso — a hand-painted brush arc from start to end with a small gap.
    let center = CGPoint(x: size / 2, y: size / 2 - size * 0.005)
    let ensoRadius = size * 0.34
    let ink = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)

    drawEnso(
        center: center,
        radius: ensoRadius,
        baseStroke: size * 0.075,
        ink: ink,
        steps: max(220, pixelSize)
    )

    // "m." text in center.
    let fontSize = size * 0.34
    let font: NSFont = {
        if let serif = NSFont(name: "Times New Roman", size: fontSize) { return serif }
        if let serif = NSFont(name: "Hoefler Text", size: fontSize) { return serif }
        return NSFont.systemFont(ofSize: fontSize, weight: .light)
    }()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: ink,
        .kern: -fontSize * 0.02,
    ]
    let text = NSAttributedString(string: "m.", attributes: attrs)
    let textSize = text.size()
    let textOrigin = CGPoint(
        x: center.x - textSize.width / 2,
        y: center.y - textSize.height / 2 + size * 0.005
    )
    text.draw(at: textOrigin)

    NSGraphicsContext.restoreGraphicsState()

    guard let cg = ctx.makeImage() else { fatalError("makeImage failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .png, properties: [:])!
}

/// Tiny deterministic LCG so icon output is reproducible across runs.
struct SeededRNG {
    private var state: UInt32
    init(seed: UInt32) { self.state = seed }
    mutating func next() -> CGFloat {
        state = state &* 1_103_515_245 &+ 12_345
        return CGFloat((state >> 16) & 0x7FFF) / 32_767.0
    }
    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        lo + next() * (hi - lo)
    }
    mutating func signed(_ amount: CGFloat) -> CGFloat {
        (next() - 0.5) * 2 * amount
    }
}

/// Draws an enso (zen circle) as a hand-painted brushstroke:
///   1. soft halo of ink bleed under the body,
///   2. dense main-body stamps with width and opacity variation,
///   3. dry-brush bristle streaks at the tail,
///   4. a heavier press-in halo at the start.
func drawEnso(
    center: CGPoint,
    radius: CGFloat,
    baseStroke: CGFloat,
    ink: NSColor,
    steps: Int
) {
    let startDeg: CGFloat = -8       // brush touches down just below 3-o'clock
    let endDeg: CGFloat = 300        // ~52° gap at the upper-right
    let sweep = endDeg - startDeg

    var rng = SeededRNG(seed: 0x9E37_79B9)

    func point(at t: CGFloat, radiusOffset: CGFloat = 0) -> CGPoint {
        let angle = (startDeg + sweep * t) * .pi / 180
        let r = radius + radiusOffset
        return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
    }

    // Width envelope: full body that gradually thins for the dry tail.
    func width(_ t: CGFloat) -> CGFloat {
        if t < 0.04 {
            return baseStroke * (0.55 + t * 11.25)        // 0.55 → 1.0 over the press-in
        }
        if t < 0.62 {
            let wobble = 0.94 + 0.10 * sin(t * 9.0)
            return baseStroke * wobble                     // ~0.94–1.04 of base
        }
        let k = (t - 0.62) / 0.38
        return max(baseStroke * 0.15, baseStroke * (1.0 - k * 0.78))
    }

    // Opacity envelope: solid until ~70%, then fades for the dry tail.
    func bodyAlpha(_ t: CGFloat) -> CGFloat {
        if t < 0.70 { return 0.96 }
        let k = (t - 0.70) / 0.30
        return max(0.0, 0.96 - k * 0.55)
    }

    func stamp(at p: CGPoint, size s: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: CGRect(
            x: p.x - s / 2, y: p.y - s / 2, width: s, height: s
        )).fill()
    }

    // 1) Soft ink bleed / halo under the main body.
    let haloRng = rng
    rng = haloRng
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps - 1)
        let w = width(t) * 1.55
        let alpha = 0.10 * bodyAlpha(t)
        if alpha < 0.005 { continue }
        let p = point(at: t, radiusOffset: rng.signed(baseStroke * 0.05))
        stamp(at: p, size: w, color: ink.withAlphaComponent(alpha))
    }

    // 2) Main body stamps — dense circles along the path with light jitter.
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps - 1)
        if t > 0.78 && rng.next() < 0.32 { continue }     // skip a few for dry feel
        let w = width(t)
        let alphaJitter = 0.85 + rng.next() * 0.15
        let alpha = bodyAlpha(t) * alphaJitter
        if alpha < 0.02 { continue }
        let radial = rng.signed(baseStroke * 0.05)
        let p = point(at: t, radiusOffset: radial)
        stamp(at: p, size: w, color: ink.withAlphaComponent(alpha))
    }

    // 3) Dry-brush bristle streaks: thin parallel arcs at the tail with gaps.
    let lanes = 6
    for lane in 0..<lanes {
        let laneOffset = (CGFloat(lane) - CGFloat(lanes - 1) / 2) * baseStroke * 0.20
        let segs = 90
        for s in 0..<segs {
            let t = 0.50 + 0.50 * CGFloat(s) / CGFloat(segs - 1)
            // Density grows toward the dry end.
            let dryProgress = (t - 0.50) / 0.50
            let skipChance = 0.78 - dryProgress * 0.20    // 0.78 → 0.58
            if rng.next() < skipChance { continue }

            let envelope = max(0, 1 - pow(dryProgress - 0.55, 2) * 4)
            let alpha = (0.18 + rng.next() * 0.30) * envelope
            if alpha < 0.02 { continue }
            let stampSize = baseStroke * (0.09 + rng.next() * 0.08)
            let radial = laneOffset + rng.signed(baseStroke * 0.03)
            let p = point(at: t, radiusOffset: radial)
            stamp(at: p, size: stampSize, color: ink.withAlphaComponent(alpha))
        }
    }

    // 4) Press-in halo at the start where the brush first contacts the page.
    let startPt = point(at: 0)
    stamp(at: startPt, size: baseStroke * 1.55, color: ink.withAlphaComponent(0.22))
    stamp(at: startPt, size: baseStroke * 1.05, color: ink.withAlphaComponent(0.55))
}

func writeContentsJSON(_ entries: [[String: String]]) throws {
    let payload: [String: Any] = [
        "images": entries,
        "info": ["version": 1, "author": "xcode"],
    ]
    let data = try JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
// Clear stale files
if let existing = try? fm.contentsOfDirectory(atPath: outDir) {
    for name in existing where name.hasSuffix(".png") {
        try? fm.removeItem(atPath: "\(outDir)/\(name)")
    }
}

var entries: [[String: String]] = []
for (base, scale) in macSizes {
    let pixel = base * scale
    let data = renderPNG(pixelSize: pixel)
    let filename = "icon_\(base)x\(base)@\(scale)x.png"
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
    entries.append([
        "idiom": "mac",
        "size": "\(base)x\(base)",
        "scale": "\(scale)x",
        "filename": filename,
    ])
    print("• \(filename) (\(pixel)px)")
}
try writeContentsJSON(entries)
print("Wrote Contents.json")
print("Done.")
