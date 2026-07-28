import SwiftUI

/// One drawable element of an SVG icon, mirroring the primitives used by the
/// web console's `components/icons.tsx`.
enum SVGPrimitive {
    case path(String)
    case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat)
    case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
    case polyline([CGPoint])

}

/// How an icon's geometry is painted.
enum SVGPaint {
    case stroke(width: CGFloat)
    case fill
}

/// A single glyph: geometry plus how to paint it.
struct SVGGlyph {
    let viewBox: CGFloat
    let paint: SVGPaint
    let primitives: [SVGPrimitive]

    init(viewBox: CGFloat = 24, paint: SVGPaint = .stroke(width: 2), _ primitives: [SVGPrimitive]) {
        self.viewBox = viewBox
        self.paint = paint
        self.primitives = primitives
    }
}

/// The icon set, transcribed verbatim from the design doc (which itself pulls
/// from `frontend/src/components/icons.tsx`). Keeping the path strings intact
/// means a change on the web side is a copy-paste away, not a redraw.
enum OCIcon: String, CaseIterable {
    // Navigation & chrome
    case chevronRight, chevronLeft, ellipsis, close, search, plus
    // Tab bar
    case inbox, tasks, office, monitor
    // Content
    case fileText, image, send, check, clock, eye, user, globe, lock, faceID
    case download, swap, settings, bolt, logo
    // Status bar
    case signalBars, wifi, battery, batteryCharging

    var glyph: SVGGlyph {
        switch self {

        // MARK: Navigation

        case .chevronRight:
            return SVGGlyph([.path("m9 18 6-6-6-6")])

        case .chevronLeft:
            return SVGGlyph([.path("m15 18-6-6 6-6")])

        case .ellipsis:
            return SVGGlyph(paint: .fill, [
                .circle(cx: 5, cy: 12, r: 1.9),
                .circle(cx: 12, cy: 12, r: 1.9),
                .circle(cx: 19, cy: 12, r: 1.9),
            ])

        case .close:
            return SVGGlyph([.path("M18 6 6 18"), .path("m6 6 12 12")])

        case .search:
            return SVGGlyph([
                .circle(cx: 11, cy: 11, r: 7),
                .path("m20 20-3.5-3.5"),
            ])

        case .plus:
            return SVGGlyph([.path("M12 5v14M5 12h14")])

        // MARK: Tab bar — 請示 / 任務 / 辦公室 / 監控

        case .inbox:
            return SVGGlyph([
                .polyline([.init(x: 22, y: 12), .init(x: 16, y: 12), .init(x: 14, y: 15),
                           .init(x: 10, y: 15), .init(x: 8, y: 12), .init(x: 2, y: 12)]),
                .path("M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"),
            ])

        case .tasks:
            return SVGGlyph([
                .path("M21 11v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"),
                .polyline([.init(x: 9, y: 11), .init(x: 12, y: 14), .init(x: 22, y: 4)]),
            ])

        case .office:
            return SVGGlyph([
                .path("M3 21h18"),
                .path("M5 21V7l8-4v18"),
                .path("M19 21V11l-6-4"),
                .path("M9 9v.01M9 12v.01M9 15v.01M9 18v.01"),
            ])

        case .monitor:
            return SVGGlyph([.path("M22 12h-4l-3 9L9 3l-3 9H2")])

        // MARK: Content

        case .fileText:
            return SVGGlyph([
                .path("M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"),
                .path("M14 2v6h6"),
                .path("M8 13h8M8 17h6"),
            ])

        case .image:
            return SVGGlyph([
                .rect(x: 3, y: 3, w: 18, h: 18, rx: 2),
                .circle(cx: 9, cy: 9, r: 2),
                .path("m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"),
            ])

        case .send:
            return SVGGlyph([
                .path("m22 2-7 20-4-9-9-4Z"),
                .path("M22 2 11 13"),
            ])

        case .check:
            return SVGGlyph([.path("M20 6 9 17l-5-5")])

        case .clock:
            return SVGGlyph([
                .circle(cx: 12, cy: 12, r: 9),
                .polyline([.init(x: 12, y: 7), .init(x: 12, y: 12), .init(x: 15, y: 14)]),
            ])

        case .eye:
            return SVGGlyph([
                .path("M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"),
                .circle(cx: 12, cy: 12, r: 3),
            ])

        case .user:
            return SVGGlyph([
                .path("M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"),
                .circle(cx: 12, cy: 7, r: 4),
            ])

        case .globe:
            return SVGGlyph([
                .circle(cx: 12, cy: 12, r: 9),
                .path("M3 12h18"),
                .path("M12 3a14 14 0 0 1 0 18 14 14 0 0 1 0-18Z"),
            ])

        case .lock:
            return SVGGlyph([
                .rect(x: 4, y: 10, w: 16, h: 11, rx: 2),
                .path("M8 10V7a4 4 0 0 1 8 0v3"),
            ])

        case .faceID:
            return SVGGlyph(paint: .stroke(width: 1.8), [
                .rect(x: 3, y: 3, w: 18, h: 18, rx: 5),
                .path("M8 9v1M16 9v1M9 15c1 1 5 1 6 0"),
            ])

        case .download:
            return SVGGlyph([
                .path("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"),
                .path("M7 10l5 5 5-5"),
                .path("M12 15V3"),
            ])

        /// 換手／跳到原訊息.
        case .swap:
            return SVGGlyph([
                .path("m16 3 4 4-4 4"),
                .path("M20 7H4"),
                .path("m8 21-4-4 4-4"),
                .path("M4 17h16"),
            ])

        case .settings:
            return SVGGlyph([
                .circle(cx: 12, cy: 12, r: 3),
                .path("M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z"),
            ])

        /// Lock-screen torch affordance.
        case .bolt:
            return SVGGlyph(paint: .fill, [.path("M13 2 3 14h7l-1 8 10-12h-7l1-8Z")])

        /// Brand mark — `frontend/public/logo.svg`.
        case .logo:
            return SVGGlyph(paint: .fill, [
                .circle(cx: 12, cy: 6, r: 2.2),
                .circle(cx: 6.5, cy: 16, r: 2.2),
                .circle(cx: 17.5, cy: 16, r: 2.2),
            ])

        // MARK: Status bar

        case .signalBars:
            return SVGGlyph(viewBox: 17, paint: .fill, [
                .rect(x: 0, y: 7.5, w: 3, h: 3.5, rx: 1),
                .rect(x: 4.6, y: 5.5, w: 3, h: 5.5, rx: 1),
                .rect(x: 9.2, y: 3, w: 3, h: 8, rx: 1),
                .rect(x: 13.8, y: 0.5, w: 3, h: 10.5, rx: 1),
            ])

        case .wifi:
            return SVGGlyph(viewBox: 15, paint: .stroke(width: 1.6), [
                .path("M1 3.6a9 9 0 0 1 13 0"),
                .path("M3.6 6.3a5.6 5.6 0 0 1 7.8 0"),
                .circle(cx: 7.5, cy: 9.2, r: 1),
            ])

        case .battery:
            return SVGGlyph(viewBox: 25, paint: .stroke(width: 1.2), [
                .rect(x: 0.6, y: 0.6, w: 21, h: 10.8, rx: 3),
            ])

        case .batteryCharging:
            return SVGGlyph(viewBox: 25, paint: .stroke(width: 1.2), [
                .rect(x: 0.6, y: 0.6, w: 21, h: 10.8, rx: 3),
                .path("M23.2 4.2v3.6"),
            ])
        }
    }
}

// MARK: - Rendering

/// Renders one `SVGGlyph`, uniformly fitted to its frame.
struct SVGGlyphShape: Shape {
    let glyph: SVGGlyph

    func path(in rect: CGRect) -> Path {
        var combined = Path()
        for primitive in glyph.primitives {
            switch primitive {
            case .path(let d):
                combined.addPath(SVGPathParser.path(from: d, in: rect, viewBox: glyph.viewBox))

            case .rect(let x, let y, let w, let h, let rx):
                let raw = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rx)
                combined.addPath(SVGPathParser.scaled(raw, in: rect, viewBox: glyph.viewBox))

            case .circle(let cx, let cy, let r):
                let raw = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                combined.addPath(SVGPathParser.scaled(raw, in: rect, viewBox: glyph.viewBox))

            case .polyline(let points):
                guard let first = points.first else { break }
                var raw = Path()
                raw.move(to: first)
                for point in points.dropFirst() { raw.addLine(to: point) }
                combined.addPath(SVGPathParser.scaled(raw, in: rect, viewBox: glyph.viewBox))
            }
        }
        return combined
    }
}

/// Drop-in icon view. Sizing follows the design doc's per-context sizes;
/// stroke width scales with the glyph so a 34pt icon does not look hairline.
struct Icon: View {
    let icon: OCIcon
    var size: CGFloat = 20

    init(_ icon: OCIcon, size: CGFloat = 20) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        let glyph = icon.glyph
        Group {
            switch glyph.paint {
            case .fill:
                SVGGlyphShape(glyph: glyph).fill(.foreground)
            case .stroke(let width):
                SVGGlyphShape(glyph: glyph)
                    .stroke(
                        .foreground,
                        style: StrokeStyle(
                            lineWidth: width * size / glyph.viewBox,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

/// The brand mark as it appears on the login screen and the iPad sidebar:
/// a rounded charcoal tile with the three-node glyph on top.
struct BrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 6 / 24, style: .continuous)
                .fill(Color(hex: 0x0A0A0B))
            SVGGlyphShape(glyph: SVGGlyph(paint: .fill, [
                .circle(cx: 12, cy: 6, r: 2.2),
                .circle(cx: 6.5, cy: 16, r: 2.2),
                .circle(cx: 17.5, cy: 16, r: 2.2),
            ]))
            .fill(.white)
            SVGGlyphShape(glyph: SVGGlyph(paint: .stroke(width: 1.6), [
                .path("M12 8v2.5L7 14.5M12 10.5l5 4"),
            ]))
            .stroke(.white, style: StrokeStyle(lineWidth: 1.6 * size / 24, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}
