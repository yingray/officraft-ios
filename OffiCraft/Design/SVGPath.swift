import SwiftUI
import CoreGraphics

/// Minimal SVG path-data parser.
///
/// The design doc pins the icon set to the web console's `components/icons.tsx`
/// ("圖示沿用 repo 的 icons.tsx／logo.svg，不另畫一套"). Rather than hand-redraw
/// 29 glyphs as SwiftUI shapes — which drifts the moment the web set changes —
/// we keep the original path strings verbatim and render them here.
///
/// Supports the full command set the icon library uses: M/m L/l H/h V/v C/c S/s
/// Q/q T/t A/a Z/z.
enum SVGPathParser {

    static func path(from d: String, in rect: CGRect, viewBox: CGFloat) -> Path {
        let path = CGMutablePath()
        var scanner = PathScanner(d)

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        // Reflection anchors for the smooth variants (S / T).
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var lastCommand: Character = " "

        while let command = scanner.nextCommand(previous: lastCommand) {
            let relative = command.isLowercase
            let cmd = Character(command.uppercased())

            switch cmd {
            case "M":
                guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                subpathStart = current
                path.move(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "L":
                guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "H":
                guard let x = scanner.nextNumber() else { break }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "V":
                guard let y = scanner.nextNumber() else { break }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "C":
                guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                      let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                let c1 = relative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let c2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2
                lastQuadControl = nil

            case "S":
                guard let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                let c1 = reflect(lastCubicControl, around: current)
                let c2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2
                lastQuadControl = nil

            case "Q":
                guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                let c = relative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuadControl = c
                lastCubicControl = nil

            case "T":
                guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                let c = reflect(lastQuadControl, around: current)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuadControl = c
                lastCubicControl = nil

            case "A":
                guard let rx = scanner.nextNumber(), let ry = scanner.nextNumber(),
                      let rotation = scanner.nextNumber(),
                      let largeArc = scanner.nextFlag(), let sweep = scanner.nextFlag(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                appendArc(to: path,
                          from: current, to: end,
                          rx: rx, ry: ry,
                          rotationDegrees: rotation,
                          largeArc: largeArc, sweep: sweep)
                current = end
                lastCubicControl = nil
                lastQuadControl = nil

            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil

            default:
                break
            }
            lastCommand = command
        }

        return scaled(Path(path), in: rect, viewBox: viewBox)
    }

    // MARK: - Geometry helpers

    private static func reflect(_ control: CGPoint?, around point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    /// SVG endpoint-parameterised arc → centre parameterisation (SVG 1.1 §F.6.5),
    /// then emitted as a `CGPath` arc under an ellipse transform.
    private static func appendArc(to path: CGMutablePath,
                                  from start: CGPoint,
                                  to end: CGPoint,
                                  rx: CGFloat,
                                  ry: CGFloat,
                                  rotationDegrees: CGFloat,
                                  largeArc: Bool,
                                  sweep: Bool) {
        // Degenerate radii collapse the arc to a straight line (spec F.6.2).
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Scale radii up if they are too small to span the chord (spec F.6.6.2).
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)

        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard len > 0 else { return 0 }
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let startAngle = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                          (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 {
            delta -= 2 * .pi
        } else if sweep && delta < 0 {
            delta += 2 * .pi
        }

        // Draw on a unit circle, then map it onto the (possibly rotated) ellipse.
        let transform = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: phi)
            .scaledBy(x: rx, y: ry)

        path.addArc(center: .zero,
                    radius: 1,
                    startAngle: startAngle,
                    endAngle: startAngle + delta,
                    clockwise: delta < 0,
                    transform: transform)
    }

    /// Uniformly fits the 24×24 (or 25×12, …) viewBox into the render rect.
    static func scaled(_ path: Path, in rect: CGRect, viewBox: CGFloat) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let offsetX = rect.minX + (rect.width - viewBox * scale) / 2
        let offsetY = rect.minY + (rect.height - viewBox * scale) / 2
        return path.applying(
            CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        )
    }

    // MARK: - Scanner

    /// Hand-rolled scanner. `Foundation.Scanner` cannot express SVG's arc flags,
    /// which may run together without separators (`a2 2 0 0 0 2 2`).
    private struct PathScanner {
        private let chars: [Character]
        private var index: Int = 0

        init(_ string: String) {
            chars = Array(string)
        }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == ","
                    || chars[index] == "\n" || chars[index] == "\t" || chars[index] == "\r" {
                index += 1
            }
        }

        /// Returns the next command letter, or repeats `previous` for an implicit
        /// repetition (`M 1 2 3 4` means moveto then lineto).
        mutating func nextCommand(previous: Character) -> Character? {
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter {
                index += 1
                return c
            }
            // Implicit repeat: a moveto's trailing pairs are linetos.
            switch previous {
            case "M": return "L"
            case "m": return "l"
            case " ": return nil
            default: return previous
            }
        }

        mutating func nextNumber() -> CGFloat? {
            skipSeparators()
            guard index < chars.count else { return nil }
            let start = index
            if chars[index] == "-" || chars[index] == "+" { index += 1 }
            var sawDigit = false
            while index < chars.count, chars[index].isNumber {
                index += 1
                sawDigit = true
            }
            if index < chars.count, chars[index] == "." {
                index += 1
                while index < chars.count, chars[index].isNumber {
                    index += 1
                    sawDigit = true
                }
            }
            guard sawDigit else {
                index = start
                return nil
            }
            if index < chars.count, chars[index] == "e" || chars[index] == "E" {
                let save = index
                index += 1
                if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
                var sawExp = false
                while index < chars.count, chars[index].isNumber {
                    index += 1
                    sawExp = true
                }
                if !sawExp { index = save }
            }
            return Double(String(chars[start..<index])).map { CGFloat($0) }
        }

        /// Arc flags are exactly one character wide and need no separator.
        mutating func nextFlag() -> Bool? {
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            guard c == "0" || c == "1" else { return nil }
            index += 1
            return c == "1"
        }
    }
}
