import SwiftUI

struct FileIcon: View {
    let isDirectory: Bool
    let isOpen: Bool
    let url: URL?

    @AppStorage(PreferenceKeys.accentPresetID)
    private var accentID: String = AccentPresets.defaultID
    @AppStorage(PreferenceKeys.accentTintFolders)
    private var tintFolders: Bool = false

    private var folderTint: Double { tintFolders ? 1.0 : 0.0 }

    var body: some View {
        if isDirectory {
            FolderShape(open: isOpen)
                .fill(folderFill)
                .overlay(
                    FolderShape(open: isOpen)
                        .stroke(folderStroke, lineWidth: 0.6)
                )
        } else {
            FileBadge(style: FileTypeStyle.style(for: url ?? URL(fileURLWithPath: "")))
        }
    }

    private var accent: Color {
        AccentPresets.preset(forID: accentID).color
    }

    /// Two stops in the folder fill gradient — both interpolate from the
    /// neutral `Color.primary` tone toward the accent color as the user
    /// raises the "Folder icons" tint slider.
    private var folderFill: LinearGradient {
        let topNeutral = Color.primary.opacity(0.18)
        let bottomNeutral = Color.primary.opacity(0.06)
        let topAccent = accent.opacity(0.55)
        let bottomAccent = accent.opacity(0.20)
        return LinearGradient(
            colors: [
                interpolate(topNeutral, topAccent, t: folderTint),
                interpolate(bottomNeutral, bottomAccent, t: folderTint),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var folderStroke: LinearGradient {
        let topNeutral = Color.primary.opacity(0.35)
        let bottomNeutral = Color.primary.opacity(0.10)
        let topAccent = accent.opacity(0.80)
        let bottomAccent = accent.opacity(0.35)
        return LinearGradient(
            colors: [
                interpolate(topNeutral, topAccent, t: folderTint),
                interpolate(bottomNeutral, bottomAccent, t: folderTint),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Linear blend between two colors. SwiftUI doesn't expose direct
    /// color mixing; we approximate by overlaying the second color at
    /// fractional opacity on top of the first via ZStack. For gradients
    /// we just need a stop value, so we use Color's pre-multiplied alpha.
    private func interpolate(_ a: Color, _ b: Color, t: Double) -> Color {
        // Color doesn't expose components in pure SwiftUI, so route
        // through NSColor for the math.
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .clear
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .clear
        let clamped = max(0, min(1, t))
        let r = na.redComponent     * (1 - clamped) + nb.redComponent     * clamped
        let g = na.greenComponent   * (1 - clamped) + nb.greenComponent   * clamped
        let bl = na.blueComponent   * (1 - clamped) + nb.blueComponent    * clamped
        let al = na.alphaComponent  * (1 - clamped) + nb.alphaComponent   * clamped
        return Color(red: r, green: g, blue: bl, opacity: al)
    }
}

private struct FileBadge: View {
    let style: FileTypeStyle

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            style.color.opacity(0.85),
                            style.color.opacity(0.62),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                            .stroke(LinearGradient(
                                colors: [
                                    Color.white.opacity(0.32),
                                    Color.white.opacity(0.04),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ), lineWidth: 0.5)
                    )

                if !style.letter.isEmpty {
                    Text(style.letter)
                        .font(.system(
                            size: fontSize(for: style.letter, in: size),
                            weight: .heavy,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.95))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 1)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fontSize(for letter: String, in size: CGFloat) -> CGFloat {
        switch letter.count {
        case 1:  return size * 0.62
        case 2:  return size * 0.46
        default: return size * 0.34   // for "C+", "{ }", etc.
        }
    }
}

private struct FolderShape: Shape {
    let open: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = rect.width * 0.12
        let tabWidth = rect.width * 0.42
        let tabHeight = rect.height * 0.18
        let topY = rect.minY + tabHeight

        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tabWidth - r, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + tabWidth + r * 0.5, y: topY),
            control: CGPoint(x: rect.minX + tabWidth, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - r, y: topY))
        p.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: topY),
            tangent2End: CGPoint(x: rect.maxX, y: topY + r),
            radius: r
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY),
            radius: r
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r),
            radius: r
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + r, y: rect.minY),
            radius: r
        )
        p.closeSubpath()
        return p
    }
}
