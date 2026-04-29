import SwiftUI

/// The Minimalist app symbol drawn as a SwiftUI view: a zen enso (open
/// brush circle) with a serif "m." in the center. Used for the empty-editor
/// watermark and any other in-app branding.
struct EnsoLogo: View {
    var color: Color = .primary
    var strokeRatio: CGFloat = 0.045

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                EnsoArc()
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: side * strokeRatio,
                            lineCap: .round
                        )
                    )
                Text("m.")
                    .font(.system(size: side * 0.32, weight: .regular, design: .serif))
                    .foregroundStyle(color)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct EnsoArc: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = side * 0.34
        var p = Path()
        // SwiftUI uses y-down screen coordinates; `clockwise: false` here
        // draws what reads as clockwise on screen, which leaves the
        // characteristic gap at the upper-right.
        p.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-8),
            endAngle: .degrees(300),
            clockwise: false
        )
        return p
    }
}
