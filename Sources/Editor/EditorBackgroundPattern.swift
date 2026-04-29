import SwiftUI

/// Subtle, zen-themed pattern overlays for the editor pane. Each is
/// drawn at a very low alpha so it whispers rather than competes with
/// the code. Animating is optional — when on, patterns evolve slowly
/// based on a user-controlled speed multiplier.
enum EditorBackgroundPattern: String, CaseIterable, Identifiable {
    /// No pattern. Editor pane keeps its plain background.
    case none
    /// Karesansui — raked sand garden. Horizontal lines with a gentle
    /// sine deformation. Animation: the wave drifts horizontally like
    /// wind brushing the surface.
    case sand
    /// Ripples — concentric circles radiating from the centre, like
    /// a stone breaking the surface of a still pond. Animation: rings
    /// expand outward and fade.
    case ripples
    /// Kasumi — soft mist drifting across the pane in horizontal
    /// bands. Animation: bands slide vertically.
    case mist
    /// Leaves — a quiet petal-cluster centered in the pane that breathes
    /// like the Watch Mindfulness app and pinwheels like the Photos
    /// icon. Animation: petals grow/shrink in a slow breath cycle while
    /// the whole flower drifts in rotation.
    case leaves
    /// Bonsai — a pine bonsai silhouette in the corner of the pane,
    /// with a serpentine trunk, distinct foliage pads, and gently
    /// drifting needles. The shape is generated once per app launch
    /// with small random variations baked into the trunk bends and
    /// pad placement, so each session shows a unique tree. Animation:
    /// the apex sways with each gust, branches bend on independent
    /// phases, and needles drift down through the wind.
    case bonsai
    /// Ame — raindrops landing on a still surface. Animation: each drop
    /// produces concentric rings that expand and fade. Drops are
    /// staggered so the surface always has a few in flight.
    case rain
    /// Rainfall — drops streak from the top of the pane to the bottom
    /// where they break into a small splash arc. Density modulates
    /// over time so rainfall comes in lulls and bursts (3..18 drops in
    /// flight at any moment), and drops vary in speed and column.
    case rainfall
    /// Mountains — two overlapping mountain silhouettes anchored on
    /// the left side of the pane, with a slow steady stream of small
    /// clouds drifting right-to-left across the upper area.
    case mountains

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .sand:    return "Sand Garden"
        case .ripples: return "Ripples"
        case .mist:    return "Mist"
        case .leaves:  return "Leaves"
        case .bonsai:  return "Bonsai"
        case .rain:    return "Puddle"
        case .rainfall: return "Rain"
        case .mountains: return "Mountains"
        }
    }
}

/// Pattern overlay view. Subscribes to a `TimelineView` only when the
/// pattern is animated, so a static pattern doesn't consume any redraw
/// budget. Lines render in the user's accent color (same color the
/// sidebar tint uses), with alpha biased a bit higher on dark surfaces
/// where the same alpha reads weaker.
struct EditorBackgroundPatternView: View {
    let pattern: EditorBackgroundPattern
    let animated: Bool
    let speed: Double  // 0.1 ... 2.0 — multiplied into time
    let isDarkSurface: Bool
    let accent: Color

    var body: some View {
        if pattern == .none {
            EmptyView()
        } else if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                Canvas { ctx, size in
                    let t = context.date.timeIntervalSinceReferenceDate * speed
                    PatternRenderer.draw(
                        pattern, in: ctx, size: size, time: t,
                        accent: accent, isDark: isDarkSurface
                    )
                }
            }
        } else {
            Canvas { ctx, size in
                PatternRenderer.draw(
                    pattern, in: ctx, size: size, time: 0,
                    accent: accent, isDark: isDarkSurface
                )
            }
        }
    }
}

/// Pure drawing functions split out so they can be tested or moved
/// behind a subview later without dragging SwiftUI lifecycle along.
private enum PatternRenderer {
    static func draw(
        _ pattern: EditorBackgroundPattern,
        in ctx: GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        accent: Color,
        isDark: Bool
    ) {
        guard size.width > 0, size.height > 0 else { return }
        // Accent reads weaker on dark surfaces, but a flat 1.0 on light
        // made every pattern almost invisible against a white pane —
        // bump light mode up so the rake lines, ripples, and falling
        // raindrops actually register without being loud.
        let alphaScale: Double = isDark ? 1.7 : 1.55
        switch pattern {
        case .none:    return
        case .sand:    drawSand(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        case .ripples: drawRipples(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        case .mist:    drawMist(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        case .leaves:  drawLeaves(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        case .bonsai:  drawBonsai(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        case .rain:    drawRain(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        case .rainfall: drawRainfall(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        case .mountains: drawMountains(in: ctx, size: size, time: time, ink: accent, alphaScale: alphaScale)
        }
    }

    // MARK: - Sand garden (karesansui)

    /// A handful of virtual rakes (each with three teeth) meander
    /// across the pane along layered Lissajous curves, drawing parallel
    /// trails that fade behind them. The teeth are spaced apart by a
    /// small per-rake jitter so each group reads as a hand-raked
    /// triple-line, not a perfectly geometric one.
    private static func drawSand(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        let rakeCount = 3            // user asked for "2-5 groups" — pick the middle.
        let teethPerRake = 3
        let trailDuration: Double = 28.0
        let segments = 110
        // Lower per-line alpha because we now stack multiple groups
        // with three teeth each — total ink quantity stays whisper-quiet.
        let alphaPeak = 0.11 * alphaScale

        // Warm-up so a non-animated pane already shows pattern instead
        // of an empty surface waiting for the rake to move.
        let warmedTime = time + 90
        let dt = trailDuration / Double(segments)

        for rakeIdx in 0..<rakeCount {
            let teethOffsets = teethOffsets(forRake: rakeIdx, count: teethPerRake)

            for i in 0..<segments {
                let tHead = warmedTime - Double(i) * dt
                let tTail = warmedTime - Double(i + 1) * dt
                let pHead = rakePosition(at: tHead, rake: rakeIdx, in: size)
                let pTail = rakePosition(at: tTail, rake: rakeIdx, in: size)

                // Perpendicular direction to the motion, used to lay the
                // teeth alongside the rake's path.
                let dx = pHead.x - pTail.x
                let dy = pHead.y - pTail.y
                let len = sqrt(dx * dx + dy * dy)
                guard len > 0.001 else { continue }
                let perpX = -dy / len
                let perpY = dx / len

                let age = warmedTime - tHead
                let progress = age / trailDuration
                let fade = pow(1 - progress, 1.6)
                let alpha = alphaPeak * fade
                let width = 0.4 + 0.5 * fade

                for offset in teethOffsets {
                    let head = CGPoint(x: pHead.x + perpX * offset,
                                       y: pHead.y + perpY * offset)
                    let tail = CGPoint(x: pTail.x + perpX * offset,
                                       y: pTail.y + perpY * offset)
                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: head)
                    ctx.stroke(path, with: .color(ink.opacity(alpha)), lineWidth: width)
                }
            }
        }
    }

    /// Tooth offsets perpendicular to the rake's motion. Each rake gets
    /// its own pseudo-random jitter so the three lines aren't perfectly
    /// equidistant — looks hand-pulled rather than stamped.
    private static func teethOffsets(forRake rakeIdx: Int, count: Int) -> [CGFloat] {
        let baseSpacing: CGFloat = 5.5
        let variance: CGFloat = 1.6
        return (0..<count).map { i in
            let centeredIdx = CGFloat(i) - CGFloat(count - 1) / 2.0
            // Deterministic jitter via the same noise hash used elsewhere.
            let n = Double(rakeIdx + 1) * 17.0 + Double(i) * 1.5
            let raw = sin(n * 31.4) * 43758.5453
            let jitter = (CGFloat(raw - floor(raw)) - 0.5) * variance * 2
            return centeredIdx * baseSpacing + jitter
        }
    }

    /// Position of rake `rakeIdx`'s head at time `t`. Layered sinusoids
    /// give long arcing sweeps with smaller cross-motions, and a phase
    /// offset per rake so the groups don't trace identical paths.
    /// Amplitudes are sized off `(half - margin)` so even the rake's
    /// peak position plus tooth offsets stays well inside the pane —
    /// previously the path could reach the edge and tooth offsets
    /// pushed individual strokes a few points outside it, which fed
    /// into the editor's word-wrap container width calculation and
    /// produced a phantom horizontal scroller.
    private static func rakePosition(at t: Double, rake rakeIdx: Int, in size: CGSize) -> CGPoint {
        let cx = size.width / 2
        let cy = size.height / 2
        let margin: CGFloat = 18  // generous: tooth offsets max out ≈7pt
        let halfX = max(size.width / 2 - margin, 1)
        let halfY = max(size.height / 2 - margin, 1)
        let primaryAx = halfX * 0.78
        let primaryAy = halfY * 0.78
        let secondaryAx = halfX * 0.18
        let secondaryAy = halfY * 0.18

        let omega1: Double = 0.11
        let omega2: Double = 0.17
        let omega3: Double = 0.43
        let omega4: Double = 0.31

        // Each rake gets its own phase offset so the three groups
        // diverge naturally instead of overlapping pixel-for-pixel.
        let phase = Double(rakeIdx) * 2.4

        let x = cx + primaryAx * sin(omega1 * t + phase)
                   + secondaryAx * sin(omega3 * t + phase * 1.3)
        let y = cy + primaryAy * sin(omega2 * t + phase * 0.7 + .pi / 3)
                   + secondaryAy * sin(omega4 * t + phase * 0.5)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Ripples

    /// Multiple ripple sources at deterministic pseudo-random positions
    /// across the pane. Each source runs the same continuous expanding-
    /// rings animation, with its own phase offset so the rings aren't
    /// in sync — looks like several stones dropped into the same still
    /// pond.
    private static func drawRipples(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        let sourceCount = 4    // user asked for "between 2 and 6" — pick a balanced middle.
        let perSourceMaxR = min(size.width, size.height) * 0.42
        let ringSpacing: CGFloat = 50
        let ringSpeed: Double = 6
        let inset: CGFloat = 36

        for i in 0..<sourceCount {
            let n = Double(i + 1) * 1.7
            // Real noise hash for the source's position so each ripple
            // truly lands at a different spot rather than repeating.
            let xRaw = sin(n * 12.9898 + 23.1) * 43758.5453
            let yRaw = sin(n * 78.2330 + 71.7) * 43758.5453
            let pRaw = sin(n * 41.7000 + 11.3) * 43758.5453
            let xFrac = xRaw - floor(xRaw)
            let yFrac = yRaw - floor(yRaw)
            let phaseFrac = pRaw - floor(pRaw)

            let cx = inset + CGFloat(xFrac) * (size.width - inset * 2)
            let cy = inset + CGFloat(yFrac) * (size.height - inset * 2)

            // Each source gets a unique time offset so they don't all
            // pulse together — feels more organic.
            let phaseOffset = phaseFrac * Double(ringSpacing) / ringSpeed
            let head = CGFloat((time + phaseOffset) * ringSpeed)
                .truncatingRemainder(dividingBy: ringSpacing)

            var r = head
            while r < perSourceMaxR {
                let normalized = r / perSourceMaxR
                let fade = sin(Double(normalized) * .pi)
                let alpha = 0.18 * fade * alphaScale
                let rect = CGRect(
                    x: cx - r, y: cy - r,
                    width: r * 2, height: r * 2
                )
                ctx.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(alpha)), lineWidth: 0.6)
                r += ringSpacing
            }
        }
    }

    // MARK: - Mist

    /// Up to 9 fuzzy blobs of varied size and aspect ratio drifting
    /// slowly across the pane while each fades in and out on its own
    /// schedule. Each blob is rendered as a radial-gradient ellipse
    /// with a softer secondary lobe offset slightly, giving it an
    /// irregular cloud-like silhouette instead of a clean oval.
    private static func drawMist(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        let blobCount = 9
        let alphaPeak = 0.16 * alphaScale

        for slot in 0..<blobCount {
            let n = Double(slot + 1) * 7.3

            // Per-slot stable shape and motion parameters.
            let baseSize: CGFloat = 90 + CGFloat(hash01(n * 1.10)) * 150   // 90..240pt
            let aspect:   CGFloat = 0.55 + CGFloat(hash01(n * 1.70)) * 0.85  // 0.55..1.40
            let vxNorm:   CGFloat = CGFloat(hash01(n * 2.30)) * 2 - 1        // -1..1
            let vyNorm:   CGFloat = CGFloat(hash01(n * 3.10)) * 2 - 1
            // Mist drifts mostly sideways, gently up/down.
            let speed: CGFloat = 4 + CGFloat(hash01(n * 4.10)) * 4           // 4..8 px/s
            let vx = vxNorm * speed
            let vy = vyNorm * speed * 0.35

            // Wraparound travel range — large enough that each blob fully
            // exits the visible pane before reappearing on the other side.
            let extX = size.width + baseSize * 2
            let extY = size.height + baseSize * 2
            let startX = CGFloat(hash01(n * 6.10)) * size.width
            let startY = CGFloat(hash01(n * 7.90)) * size.height
            let cx = wrapPositive(startX + vx * CGFloat(time), range: extX) - baseSize
            let cy = wrapPositive(startY + vy * CGFloat(time), range: extY) - baseSize

            // Independent fade cycle: each blob gets its own period and
            // phase offset, so the field never blinks in unison.
            let fadePeriod = 10.0 + hash01(n * 4.70) * 14.0       // 10..24 s
            let fadePhase = hash01(n * 5.30) * fadePeriod
            let fadeT = ((time + fadePhase) / fadePeriod).truncatingRemainder(dividingBy: 1)
            let lifecycle = (1 - cos(fadeT * 2 * .pi)) / 2       // 0 → 1 → 0
            let alpha = alphaPeak * lifecycle
            if alpha < 0.005 { continue }

            // Main lobe.
            drawSoftBlob(
                in: ctx,
                center: CGPoint(x: cx, y: cy),
                width: baseSize,
                height: baseSize * aspect,
                ink: ink,
                alpha: alpha
            )
            // Secondary lobe — offset and smaller, so the silhouette
            // reads as an irregular blob rather than a perfect ellipse.
            let secOffsetX = baseSize * 0.32 * CGFloat(hash01(n * 8.10) - 0.5)
            let secOffsetY = baseSize * 0.22 * CGFloat(hash01(n * 9.30) - 0.5)
            let secW = baseSize * (0.50 + CGFloat(hash01(n * 10.7)) * 0.25)
            let secH = secW * aspect * (0.85 + CGFloat(hash01(n * 11.5)) * 0.30)
            drawSoftBlob(
                in: ctx,
                center: CGPoint(x: cx + secOffsetX, y: cy + secOffsetY),
                width: secW,
                height: secH,
                ink: ink,
                alpha: alpha * 0.70
            )
        }
    }

    /// One soft, fading blob — radial gradient from full alpha at the
    /// center to transparent at the edge, painted onto an ellipse.
    private static func drawSoftBlob(
        in ctx: GraphicsContext,
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        ink: Color,
        alpha: Double
    ) {
        let rect = CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width, height: height
        )
        let gradient = Gradient(stops: [
            .init(color: ink.opacity(alpha),         location: 0.0),
            .init(color: ink.opacity(alpha * 0.55),  location: 0.45),
            .init(color: ink.opacity(0),             location: 1.0),
        ])
        ctx.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                gradient,
                center: center,
                startRadius: 0,
                endRadius: max(width, height) / 2
            )
        )
    }

    /// Modulo that always returns a non-negative result for positive
    /// `range`. Used to wrap blob positions cleanly without producing
    /// negative wrapped offsets when the input is negative.
    private static func wrapPositive(_ value: CGFloat, range: CGFloat) -> CGFloat {
        guard range > 0 else { return value }
        let r = value.truncatingRemainder(dividingBy: range)
        return r < 0 ? r + range : r
    }

    // MARK: - Leaves

    /// A radial petal cluster in the pane's centre. Each petal is a
    /// teardrop pointed at the centre and rounded outward. The flower
    /// breathes (petals grow / shrink) and slowly rotates — the static
    /// case lands on the cycle's peak so a still pane shows a fully
    /// "open" flower rather than a collapsed one.
    private static func drawLeaves(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let petalCount = 8
        let breathCycle: Double = 8.0

        // Shift the phase so `time = 0` (static mode) lands on breath = 1
        // — the open / fullest state. During animation we cycle smoothly
        // from open → closed → open over `breathCycle` seconds.
        let shifted = (time + breathCycle / 2)
            .truncatingRemainder(dividingBy: breathCycle)
        let phase = shifted / breathCycle
        let breath = (1 - cos(phase * 2 * .pi)) / 2  // 0 → 1 → 0

        let petalLength: CGFloat = 60 + 38 * CGFloat(breath)
        let petalWidth: CGFloat = 18 + 8 * CGFloat(breath)
        let alpha = 0.20 * (0.65 + 0.35 * breath) * alphaScale
        // Whole flower drifts slowly in rotation as it breathes.
        let rotation: Double = time * 0.05

        for i in 0..<petalCount {
            let angle = Double(i) * 2 * .pi / Double(petalCount) + rotation
            // Teardrop petal in local coords: tip at the origin, rounded
            // bulge along +X. Two quadratic curves sweep above and below
            // a centre line to create the leaf shape.
            let petal = Path { p in
                p.move(to: .zero)
                p.addQuadCurve(
                    to: CGPoint(x: petalLength, y: 0),
                    control: CGPoint(x: petalLength * 0.5, y: -petalWidth)
                )
                p.addQuadCurve(
                    to: .zero,
                    control: CGPoint(x: petalLength * 0.5, y: petalWidth)
                )
                p.closeSubpath()
            }
            // Rotate the petal to its angle, then translate to centre.
            let combined = CGAffineTransform(rotationAngle: angle)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            let placed = petal.applying(combined)
            ctx.fill(placed, with: .color(ink.opacity(alpha * 0.55)))
            ctx.stroke(placed, with: .color(ink.opacity(alpha)), lineWidth: 0.6)
        }
    }

    // MARK: - Bonsai

    /// Stable per-launch random seed used by the bonsai's shape
    /// generator, so each app session shows a unique tree but it
    /// doesn't reshape on every redraw.
    private static let bonsaiSeed: Double = .random(in: 0...1000)

    /// Hash helper: 0..1 from a numeric seed via the GLSL noise trick.
    private static func hash01(_ n: Double) -> Double {
        let v = sin(n) * 43758.5453
        return v - floor(v)
    }

    /// A pine bonsai in the right side of the pane: serpentine trunk
    /// rendered as a tapered solid (thicker at the nebari, narrowing
    /// toward the apex), six manicured foliage pads on short branches,
    /// and pine needles drifting down on the wind. Trunk bends, pad
    /// placement, and pad sizes are all biased by `bonsaiSeed` so the
    /// shape varies per session while staying recognizably bonsai.
    private static func drawBonsai(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        // Pot dimensions are reserved at the bottom so the trunk can
        // emerge cleanly from its rim.
        let potHeight: CGFloat = 32
        let baseX = size.width * 0.78
        // The "ground" line — top of the pot, where the trunk meets soil.
        let baseY = min(size.height * 0.86, size.height - potHeight - 10)
        let height: CGFloat = min(size.height * 0.72, 320)

        // Wind sway. Drives apex offset, branch bend, and falling-needle drift.
        let swayPhase = time * 0.42
        let swayAmp: CGFloat = 8
        let sway = CGFloat(sin(swayPhase)) * swayAmp

        let alphaPeak = 0.14 * alphaScale

        // -- Pot --------------------------------------------------------
        // Classic shallow bonsai pot: gently trapezoidal, with a rim
        // line and two small feet. Drawn first so the trunk visually
        // emerges from it.
        let potWidth: CGFloat = 124
        let potTopInset: CGFloat = 4
        let potBottomInset: CGFloat = 14
        let potTopLeft = CGPoint(x: baseX - potWidth / 2 + potTopInset, y: baseY)
        let potTopRight = CGPoint(x: baseX + potWidth / 2 - potTopInset, y: baseY)
        let potBottomY = baseY + potHeight
        let potBottomLeft = CGPoint(x: baseX - potWidth / 2 + potBottomInset, y: potBottomY)
        let potBottomRight = CGPoint(x: baseX + potWidth / 2 - potBottomInset, y: potBottomY)

        var potShape = Path()
        potShape.move(to: potTopLeft)
        potShape.addLine(to: potTopRight)
        potShape.addLine(to: potBottomRight)
        potShape.addLine(to: potBottomLeft)
        potShape.closeSubpath()
        ctx.fill(potShape, with: .color(ink.opacity(alphaPeak * 0.85)))
        ctx.stroke(potShape, with: .color(ink.opacity(alphaPeak * 1.20)), lineWidth: 1.0)

        // Rim — a stronger horizontal hairline just inside the top.
        var rim = Path()
        rim.move(to: CGPoint(x: potTopLeft.x + 4,  y: baseY + 3))
        rim.addLine(to: CGPoint(x: potTopRight.x - 4, y: baseY + 3))
        ctx.stroke(rim, with: .color(ink.opacity(alphaPeak * 1.55)), lineWidth: 1.4)

        // Feet — small rectangles tucked under each lower corner.
        let footW: CGFloat = 16
        let footH: CGFloat = 5
        ctx.fill(
            Path(CGRect(x: potBottomLeft.x,  y: potBottomY, width: footW, height: footH)),
            with: .color(ink.opacity(alphaPeak * 0.95))
        )
        ctx.fill(
            Path(CGRect(x: potBottomRight.x - footW, y: potBottomY, width: footW, height: footH)),
            with: .color(ink.opacity(alphaPeak * 0.95))
        )

        // Per-launch shape variation — small biases on each waypoint so
        // the trunk's three segments lean differently between sessions.
        let s = bonsaiSeed
        let bend1X: CGFloat = -28 + CGFloat((hash01(s * 1.3) - 0.5) * 18)
        let bend2X: CGFloat = 22 + CGFloat((hash01(s * 2.7) - 0.5) * 20)
        let apexBiasX: CGFloat = -6 + CGFloat((hash01(s * 4.1) - 0.5) * 12)
        let pad1Length: CGFloat = 38 + CGFloat(hash01(s * 5.3) * 18)
        let pad2Length: CGFloat = 46 + CGFloat(hash01(s * 6.9) * 22)
        let pad3Length: CGFloat = 32 + CGFloat(hash01(s * 8.7) * 16)
        let pad4Length: CGFloat = 28 + CGFloat(hash01(s * 11.3) * 14)

        // Trunk waypoints. Sway leaves the base anchored, lifts the
        // higher waypoints progressively further so the apex is the
        // most affected.
        let p0 = CGPoint(x: baseX, y: baseY)
        let p1 = CGPoint(x: baseX + bend1X + sway * 0.25, y: baseY - height * 0.30)
        let p2 = CGPoint(x: baseX + bend2X + sway * 0.55, y: baseY - height * 0.62)
        let p3 = CGPoint(x: baseX + apexBiasX + sway * 0.85, y: baseY - height * 0.88)

        // Trunk: render in three stroked segments with decreasing line
        // width to give visible taper from the nebari to the apex.
        // Round line caps blend the seams between segments.
        let trunkColor = Color(ink).opacity(alphaPeak * 1.45)
        let segs: [(CGPoint, CGPoint, CGPoint, CGFloat)] = [
            (p0, CGPoint(x: baseX + bend1X * 0.4, y: baseY - height * 0.15), p1, 18),
            (p1, CGPoint(x: p1.x + (bend2X - bend1X) * 0.4, y: baseY - height * 0.46), p2, 12),
            (p2, CGPoint(x: p2.x + (apexBiasX - bend2X) * 0.4, y: baseY - height * 0.78), p3, 6),
        ]
        for (start, control, end, width) in segs {
            var seg = Path()
            seg.move(to: start)
            seg.addQuadCurve(to: end, control: control)
            ctx.stroke(seg, with: .color(trunkColor), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        // Subtle nebari (root flare) — two small horizontal arcs at the
        // base, suggesting root spread without drawing actual roots.
        let flareR: CGFloat = 11
        for side: CGFloat in [-1, 1] {
            let cx = baseX + side * 7
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - flareR / 2, y: baseY - 4, width: flareR, height: 7)),
                with: .color(ink.opacity(alphaPeak * 0.8))
            )
        }

        // Foliage pad descriptors: anchor on trunk, branch direction,
        // length, pad size. Six manicured pads at varying heights —
        // larger toward the lower trunk, smaller toward the apex,
        // following classic bonsai composition.
        let p1p2Mid = CGPoint(
            x: (p1.x + p2.x) / 2 + sway * 0.4,
            y: (p1.y + p2.y) / 2
        )
        let p2p3Mid = CGPoint(
            x: (p2.x + p3.x) / 2 + sway * 0.7,
            y: (p2.y + p3.y) / 2
        )
        let pads: [PadDescriptor] = [
            // Lower-left primary pad (the bonsai's biggest, off the first bend).
            PadDescriptor(
                anchor: p1, branchDir: -1, length: pad1Length,
                padSize: CGSize(width: 96, height: 38),
                swayPhase: 0.3, seed: s + 1.0
            ),
            // Lower-right counter-balance, smaller.
            PadDescriptor(
                anchor: p1, branchDir: 1, length: pad1Length * 0.55,
                padSize: CGSize(width: 56, height: 26),
                swayPhase: 0.9, seed: s + 1.7
            ),
            // Mid-right large pad, off the second bend.
            PadDescriptor(
                anchor: p2, branchDir: 1, length: pad2Length,
                padSize: CGSize(width: 104, height: 40),
                swayPhase: 1.4, seed: s + 2.5
            ),
            // Mid-left smaller pad, providing visual balance.
            PadDescriptor(
                anchor: p1p2Mid, branchDir: -1, length: pad3Length,
                padSize: CGSize(width: 64, height: 28),
                swayPhase: 2.0, seed: s + 3.7
            ),
            // Upper-left small pad.
            PadDescriptor(
                anchor: p2p3Mid, branchDir: -1, length: pad4Length,
                padSize: CGSize(width: 52, height: 24),
                swayPhase: 2.6, seed: s + 4.5
            ),
            // Apex cap — directly on top, rounded crown.
            PadDescriptor(
                anchor: p3, branchDir: 0, length: 0,
                padSize: CGSize(width: 64, height: 30),
                swayPhase: 3.1, seed: s + 5.2
            ),
        ]

        for pad in pads {
            // Branch from anchor to pad centre. Skip for the apex pad
            // (length 0) — that one sits directly on the trunk.
            let bend = CGFloat(sin(time * 0.5 + pad.swayPhase)) * 3
            let padCenter = CGPoint(
                x: pad.anchor.x + pad.branchDir * pad.length + bend * pad.branchDir,
                y: pad.anchor.y - 10
            )
            if pad.length > 0 {
                drawBonsaiBranch(from: pad.anchor, to: padCenter, in: ctx, ink: ink, alpha: alphaPeak * 0.95)
            }
            drawBonsaiPad(
                at: padCenter, width: pad.padSize.width, height: pad.padSize.height,
                in: ctx, ink: ink, alpha: alphaPeak,
                time: time, seed: pad.seed
            )
        }

        // Falling needles — event-stream of tiny rotated line segments
        // spawning from random pads. Tuned to be visible: a higher
        // spawn rate, longer line, slightly thicker stroke, and a
        // healthy alpha boost so the needles register against the
        // editor background even in light mode.
        let fallRate: Double = 0.85
        let fallDuration: Double = 7.0
        let warmedTime = time + 30
        let currentIdx = Int(floor(warmedTime * fallRate))
        let oldestIdx = max(0, Int(floor((warmedTime - fallDuration) * fallRate)))
        guard oldestIdx <= currentIdx else { return }

        for idx in oldestIdx...currentIdx {
            let birth = Double(idx) / fallRate
            let age = warmedTime - birth
            guard age >= 0, age <= fallDuration else { continue }

            let n = Double(idx + 200) + bonsaiSeed
            // Pick a pad to spawn from at random.
            let padIdx = min(pads.count - 1,
                             Int(floor(hash01(n * 41.7) * Double(pads.count))))
            let pad = pads[padIdx]
            let bend = CGFloat(sin(time * 0.5 + pad.swayPhase)) * 3
            let padCenter = CGPoint(
                x: pad.anchor.x + pad.branchDir * pad.length + bend * pad.branchDir,
                y: pad.anchor.y - 10
            )

            // Spawn position within the pad's lower half (needles fall
            // off the bottom edge) plus a small horizontal spread.
            let xFrac = hash01(n * 12.9) - 0.5
            let yFrac = hash01(n * 78.2) * 0.5      // 0..0.5 — lower half of pad
            let startX = padCenter.x + CGFloat(xFrac) * pad.padSize.width * 0.85
            let startY = padCenter.y + CGFloat(yFrac) * pad.padSize.height

            let progress = age / fallDuration
            let fallDist: CGFloat = 110 + 70 * CGFloat(hash01(n * 19.3))
            let yPos = startY + CGFloat(progress) * fallDist
            // Horizontal sway gets stronger as the needle tumbles.
            let xSway = CGFloat(sin(age * 1.8 + n)) * (4 + 4 * CGFloat(progress))
            let xPos = startX + xSway + sway * 0.55

            // Needle: rotated line segment biased toward more vertical
            // angles, since real falling needles tend to align with
            // their fall direction.
            let needleAngle = (hash01(n * 31.7) * 0.6 + 0.2) * .pi   // 0.2π..0.8π
            let needleLength: CGFloat = 5.5 + 2 * CGFloat(hash01(n * 53.1))
            let dx = CGFloat(cos(needleAngle)) * needleLength
            let dy = CGFloat(sin(needleAngle)) * needleLength

            // Stronger alpha + longer hold than before so each needle
            // is clearly visible across most of its fall.
            let lifeFade = sin(progress * .pi)
            let alpha = alphaPeak * 1.6 * lifeFade
            var path = Path()
            path.move(to: CGPoint(x: xPos - dx / 2, y: yPos - dy / 2))
            path.addLine(to: CGPoint(x: xPos + dx / 2, y: yPos + dy / 2))
            ctx.stroke(
                path,
                with: .color(ink.opacity(alpha)),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
            )
        }
    }

    /// One pad of pine foliage anchored on the trunk.
    private struct PadDescriptor {
        let anchor: CGPoint
        let branchDir: CGFloat   // -1, 0, or +1
        let length: CGFloat
        let padSize: CGSize
        let swayPhase: Double    // adds variety to per-pad branch motion
        let seed: Double         // drives needle-dot placement inside the pad
    }

    private static func drawBonsaiBranch(
        from start: CGPoint, to end: CGPoint,
        in ctx: GraphicsContext, ink: Color, alpha: Double
    ) {
        let cp = CGPoint(
            x: (start.x + end.x) / 2 + (end.x - start.x) * 0.06,
            y: (start.y + end.y) / 2 - 3
        )
        var branch = Path()
        branch.move(to: start)
        branch.addQuadCurve(to: end, control: cp)
        ctx.stroke(branch, with: .color(ink.opacity(alpha)), lineWidth: 1.2)
    }

    /// Draws one foliage pad. The body is a few overlapping ellipses
    /// arranged in a horizontal cluster — gives the manicured "cloud"
    /// silhouette that distinguishes a bonsai pad from a plain oval —
    /// then needle dots are sprinkled across the body.
    private static func drawBonsaiPad(
        at center: CGPoint, width: CGFloat, height: CGFloat,
        in ctx: GraphicsContext, ink: Color, alpha: Double,
        time: TimeInterval, seed: Double
    ) {
        // 4–5 overlapping bumps build the cloud body. Bump positions
        // are hashed off the seed so each pad is shaped differently.
        let bumpCount = 5
        for i in 0..<bumpCount {
            let n = seed * 7.0 + Double(i) * 1.9
            let xFrac = hash01(n * 12.9) - 0.5
            let yFrac = hash01(n * 78.2) - 0.5
            let bumpW = height * (1.4 + CGFloat(hash01(n * 31.7)) * 0.6)
            let bumpH = height * (0.9 + CGFloat(hash01(n * 41.3)) * 0.4)
            let bx = center.x + CGFloat(xFrac) * width * 0.55
            let by = center.y + CGFloat(yFrac) * height * 0.4
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: bx - bumpW / 2, y: by - bumpH / 2,
                    width: bumpW, height: bumpH
                )),
                with: .color(ink.opacity(alpha * 0.30))
            )
        }

        // Needle dots scattered across the pad's bounding box. Density
        // scales with size so larger pads aren't sparser.
        let area = Double(width * height)
        let dotCount = max(14, Int(area / 60))
        for i in 0..<dotCount {
            let n = Double(i + 1) * 1.7 + seed * 13.0
            let xFrac = hash01(n * 12.9) - 0.5
            let yFrac = hash01(n * 78.2) - 0.5
            let px = center.x + CGFloat(xFrac) * width * 0.85
            let py = center.y + CGFloat(yFrac) * height * 0.85
            let wobble = CGFloat(sin(time * 0.5 + n)) * 1.0
            let dotR: CGFloat = 1.5
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: px - dotR + wobble,
                    y: py - dotR,
                    width: dotR * 2, height: dotR * 2
                )),
                with: .color(ink.opacity(alpha * 0.85))
            )
        }
    }

    // MARK: - Rain

    /// A sparse, contemplative rain — at most a handful of drops alive
    /// at any moment, expanding outward and *bouncing* off the pane's
    /// edges via the optical method-of-images: for each wall a mirror-
    /// image ring is drawn at the reflected centre, so the visible arc
    /// inside the pane reads as a wavefront returning from the wall.
    /// User's speed slider directly controls how often new drops fall.
    private static func drawRain(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        // Sparse on purpose — average ~1.6 drops in flight.
        let dropRate: Double = 0.4               // drops per (scaled) second
        let lifetime: Double = 5.2               // single ripple's lifespan
        let waveSpeed: CGFloat = 70              // pt / lifetime-second
        let alphaPeak: Double = 0.20 * alphaScale

        // Warm-up so static and just-started panes already have
        // something to show.
        let warmedTime = time + 30

        let currentIdx = Int(floor(warmedTime * dropRate))
        let oldestIdx = max(0, Int(floor((warmedTime - lifetime) * dropRate)))
        guard oldestIdx <= currentIdx else { return }

        for idx in oldestIdx...currentIdx {
            let birth = Double(idx) / dropRate
            let age = warmedTime - birth
            guard age >= 0, age <= lifetime else { continue }

            // Place the drop with a real noise hash. The previous
            // `fmod(seed * 73, 1)` collapsed to a constant for any
            // integer step in `seed`, so every drop landed at the same
            // spot. The classic GLSL `fract(sin(n) * 43758.5453)` trick
            // gives a uniform-looking pseudo-random value per index;
            // different multipliers keep x and y uncorrelated.
            let inset: CGFloat = 24
            let n = Double(idx) + 1.0
            let rawX = sin(n * 12.9898 + 23.1) * 43758.5453
            let rawY = sin(n * 78.2330 + 71.7) * 43758.5453
            let fracX = rawX - floor(rawX)
            let fracY = rawY - floor(rawY)
            let x = inset + CGFloat(fracX) * (size.width  - inset * 2)
            let y = inset + CGFloat(fracY) * (size.height - inset * 2)

            let phase = age / lifetime              // 0..1
            let radius = CGFloat(phase) * waveSpeed * CGFloat(lifetime) * 0.6
            // Smooth rise + fall of intensity through the ripple's life.
            let intensity = sin(phase * .pi)
            let alpha = alphaPeak * intensity

            // Helper that strokes a circle at a given centre. Used for
            // both the original ripple and each wall reflection.
            func stroke(at center: CGPoint, alpha: Double, width: CGFloat) {
                guard alpha > 0.001, radius > 0 else { return }
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                ctx.stroke(
                    Path(ellipseIn: rect),
                    with: .color(ink.opacity(alpha)),
                    lineWidth: width
                )
            }

            // Original ripple — primary wave + a fainter inner one
            // trailing slightly so each drop reads as a multi-crest
            // ripple, not a single circle.
            stroke(at: CGPoint(x: x, y: y), alpha: alpha, width: 0.7)
            let innerRadius = radius * 0.62
            if innerRadius > 0 {
                let rect = CGRect(
                    x: x - innerRadius, y: y - innerRadius,
                    width: innerRadius * 2, height: innerRadius * 2
                )
                ctx.stroke(
                    Path(ellipseIn: rect),
                    with: .color(ink.opacity(alpha * 0.55)),
                    lineWidth: 0.5
                )
            }

            // Wall reflections — only render when the wave has actually
            // reached the wall. Energy lost to reflection: 60% as fade.
            let reflectAlpha = alpha * 0.60
            // Left wall: visible when radius > x
            if radius > x {
                stroke(at: CGPoint(x: -x, y: y), alpha: reflectAlpha, width: 0.55)
            }
            // Right wall
            if radius > (size.width - x) {
                stroke(at: CGPoint(x: 2 * size.width - x, y: y), alpha: reflectAlpha, width: 0.55)
            }
            // Top wall
            if radius > y {
                stroke(at: CGPoint(x: x, y: -y), alpha: reflectAlpha, width: 0.55)
            }
            // Bottom wall
            if radius > (size.height - y) {
                stroke(at: CGPoint(x: x, y: 2 * size.height - y), alpha: reflectAlpha, width: 0.55)
            }
        }
    }

    // MARK: - Rainfall

    /// Streaking rain. A pool of drop "slots" each cycle through fall
    /// → splash, with random column, speed, and timing. The number of
    /// active slots is gated by a slow density envelope so rainfall
    /// drifts between lulls (≈3 drops in flight) and bursts (≈18).
    private static func drawRainfall(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        // Gentle warm-up so a paused pane is mid-storm rather than empty.
        let warmedTime = time + 8

        // Density envelope: slow oscillation between sparse and heavy.
        // Two layered sines so the pattern doesn't repeat predictably
        // every cycle.
        let densityPhase1 = warmedTime * 0.045
        let densityPhase2 = warmedTime * 0.013
        let dRaw = (sin(densityPhase1) + 0.6 * sin(densityPhase2)) / 1.6
        let density = (dRaw + 1) / 2  // 0..1
        let minDrops = 3
        let maxDrops = 18
        let activeSlots = minDrops + Int(round(density * Double(maxDrops - minDrops)))

        let alphaPeak = 0.20 * alphaScale
        let fallFrac: Double = 0.86
        let bottomY = size.height

        for slot in 0..<activeSlots {
            let n = Double(slot + 1) * 7.3 + bonsaiSeed * 0.001  // tiny extra entropy

            // Per-slot speed (0.55..1.5) → period (1.7s..1.4s base).
            let speed = 0.55 + hash01(n * 1.7) * 0.95
            let basePeriod: Double = 2.4 / speed

            // Slight slot-specific phase offset so drops don't all
            // start at the same instant.
            let slotPhaseOffset = hash01(n * 5.1) * basePeriod

            let cyclesElapsed = (warmedTime + slotPhaseOffset) / basePeriod
            let cycleNum = Int(floor(cyclesElapsed))
            let phase = cyclesElapsed - Double(cycleNum)  // 0..1 within the slot's current cycle

            // Each new cycle picks a fresh column, so the same slot
            // doesn't keep dropping into the same x.
            let cycleSeed = n + Double(cycleNum) * 13.71
            let xRaw = hash01(cycleSeed * 12.9)
            let inset: CGFloat = 8
            let xPos = inset + CGFloat(xRaw) * (size.width - inset * 2)

            if phase < fallFrac {
                // Falling streak — vertical line. Length scales with
                // speed (faster drops streak longer).
                let fallProgress = CGFloat(phase / fallFrac)
                let dropY = fallProgress * bottomY
                let streakLen: CGFloat = 5 + 8 * CGFloat(speed - 0.55) / 0.95
                let drop = Path { p in
                    p.move(to: CGPoint(x: xPos, y: max(0, dropY - streakLen)))
                    p.addLine(to: CGPoint(x: xPos, y: dropY))
                }
                ctx.stroke(
                    drop,
                    with: .color(ink.opacity(alphaPeak)),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                )
            } else {
                // Splash — small arc rising from the bottom edge that
                // expands outward and fades as it dissipates.
                let splashProgress = (phase - fallFrac) / (1.0 - fallFrac)  // 0..1
                let splashR: CGFloat = 1 + CGFloat(splashProgress) * 9
                let splashAlpha = alphaPeak * (1 - splashProgress)
                let splash = Path { p in
                    p.move(to: CGPoint(x: xPos - splashR, y: bottomY))
                    p.addQuadCurve(
                        to: CGPoint(x: xPos + splashR, y: bottomY),
                        control: CGPoint(x: xPos, y: bottomY - splashR * 0.8)
                    )
                }
                ctx.stroke(
                    splash,
                    with: .color(ink.opacity(splashAlpha)),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
                )
                // A pair of tiny droplet specks flying off the splash
                // for the heavier impacts (later half of life only).
                if splashProgress < 0.6 && speed > 0.85 {
                    let speckR: CGFloat = 1.0
                    let speckSpread: CGFloat = splashR * 1.1
                    let speckY = bottomY - splashR * 0.5
                    for side: CGFloat in [-1, 1] {
                        ctx.fill(
                            Path(ellipseIn: CGRect(
                                x: xPos + side * speckSpread - speckR,
                                y: speckY - speckR,
                                width: speckR * 2, height: speckR * 2
                            )),
                            with: .color(ink.opacity(splashAlpha * 0.85))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Mountains

    /// Two overlapping mountain silhouettes anchored on the left of
    /// the pane, plus a slow continuous stream of small clouds
    /// drifting right-to-left across the upper area. Mountains are
    /// stationary; cloud positions, sizes, and Y heights are hashed
    /// per cloud-event so each one varies.
    private static func drawMountains(in ctx: GraphicsContext, size: CGSize, time: TimeInterval, ink: Color, alphaScale: Double) {
        let alphaBase = 0.18 * alphaScale
        let baselineY = size.height * 0.93

        // Back mountain — taller, slightly off-screen left so its
        // base reads as continuing past the pane edge.
        let m1BaseLeft  = CGPoint(x: -size.width * 0.05, y: baselineY)
        let m1Peak      = CGPoint(x:  size.width * 0.18, y: baselineY - size.height * 0.50)
        let m1BaseRight = CGPoint(x:  size.width * 0.42, y: baselineY)
        drawMountainSilhouette(
            in: ctx,
            baseLeft: m1BaseLeft, peak: m1Peak, baseRight: m1BaseRight,
            ink: ink, alpha: alphaBase * 0.70
        )

        // Front mountain — shorter, offset right of the back one so
        // they read as layered peaks rather than concentric.
        let m2BaseLeft  = CGPoint(x: size.width * 0.10, y: baselineY)
        let m2Peak      = CGPoint(x: size.width * 0.32, y: baselineY - size.height * 0.34)
        let m2BaseRight = CGPoint(x: size.width * 0.55, y: baselineY)
        drawMountainSilhouette(
            in: ctx,
            baseLeft: m2BaseLeft, peak: m2Peak, baseRight: m2BaseRight,
            ink: ink, alpha: alphaBase * 1.05
        )

        // Cloud stream — soft blobs born just past the right edge,
        // drifting steadily to the left, fading in/out at the edges.
        let cloudSpeed: CGFloat = 9
        let cloudRate: Double = 0.18                // ~1 every 5.5 s
        let warmedTime = time + 100                 // long warm-up so a static pane is mid-stream
        let entryX: CGFloat = size.width + 100
        let exitX: CGFloat = -200
        let lifetime: Double = Double((entryX - exitX) / cloudSpeed)

        let currentIdx = Int(floor(warmedTime * cloudRate))
        let oldestIdx = max(0, Int(floor((warmedTime - lifetime) * cloudRate)))
        guard oldestIdx <= currentIdx else { return }

        for idx in oldestIdx...currentIdx {
            let birth = Double(idx) / cloudRate
            let age = warmedTime - birth
            guard age >= 0, age <= lifetime else { continue }

            let n = Double(idx + 300)

            // Cloud drifts steadily right-to-left.
            let xPos = entryX - cloudSpeed * CGFloat(age)

            // Hashed Y in the upper part of the pane (5%..50% from top).
            let yFrac = 0.05 + hash01(n * 12.9) * 0.45
            let yPos = CGFloat(yFrac) * size.height

            let sizeRaw = hash01(n * 78.2)
            let cloudW: CGFloat = 60 + 90 * CGFloat(sizeRaw)
            let cloudH: CGFloat = cloudW * (0.30 + 0.18 * CGFloat(hash01(n * 41.0)))

            // Fade in at right edge, fade out at left edge.
            let progress = age / lifetime
            let fadeIn = min(1.0, progress / 0.12)
            let fadeOut = min(1.0, (1.0 - progress) / 0.12)
            let fade = min(fadeIn, fadeOut)
            let cloudAlpha = alphaBase * 0.55 * fade
            if cloudAlpha < 0.005 { continue }

            // Main lobe + a smaller offset secondary lobe to give the
            // cloud an irregular, hand-drawn silhouette.
            drawSoftBlob(
                in: ctx,
                center: CGPoint(x: xPos, y: yPos),
                width: cloudW, height: cloudH,
                ink: ink, alpha: cloudAlpha
            )
            let secOffsetX = cloudW * 0.28 * CGFloat(hash01(n * 8.1) - 0.5)
            let secOffsetY = cloudH * 0.22 * CGFloat(hash01(n * 9.3) - 0.5)
            drawSoftBlob(
                in: ctx,
                center: CGPoint(x: xPos + secOffsetX, y: yPos + secOffsetY),
                width: cloudW * 0.55,
                height: cloudH * 0.85,
                ink: ink, alpha: cloudAlpha * 0.70
            )
        }
    }

    /// One mountain silhouette — two quadratic curves from each base
    /// to the peak, closing back along the baseline. Filled with a
    /// soft alpha; the curve's control points sit slightly under the
    /// peak so the slopes have a natural cool-mountain bell rather
    /// than sharp triangle edges.
    private static func drawMountainSilhouette(
        in ctx: GraphicsContext,
        baseLeft: CGPoint, peak: CGPoint, baseRight: CGPoint,
        ink: Color, alpha: Double
    ) {
        var path = Path()
        path.move(to: baseLeft)
        path.addQuadCurve(
            to: peak,
            control: CGPoint(
                x: baseLeft.x + (peak.x - baseLeft.x) * 0.55,
                y: baseLeft.y + (peak.y - baseLeft.y) * 0.65
            )
        )
        path.addQuadCurve(
            to: baseRight,
            control: CGPoint(
                x: peak.x + (baseRight.x - peak.x) * 0.45,
                y: peak.y + (baseRight.y - peak.y) * 0.40
            )
        )
        path.addLine(to: baseLeft)
        path.closeSubpath()
        ctx.fill(path, with: .color(ink.opacity(alpha)))
    }
}
