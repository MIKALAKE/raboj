import CoreGraphics
import Foundation

/// Converts SVG path data (`d` attribute) into a `CGPath`.
/// Supports every path command: M L H V C S Q T A Z, absolute and relative.
public enum SVGPath {
    public static func cgPath(_ d: String) -> CGPath {
        var scanner = Tokens(Array(d.utf8))
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: UInt8 = 0
        var command: UInt8 = 0

        while scanner.skipSeparators() {
            if let c = scanner.command() {
                command = c
            } else if command == 0 {
                break
            }
            let relative = command >= 97 // lowercase
            let base = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: base.x + x, y: base.y + y)
            }
            let upper = relative ? command - 32 : command
            var nextControl: CGPoint?

            switch upper {
            case UInt8(ascii: "M"):
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                // Further coordinate pairs after M are implicit L commands.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "L"):
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case UInt8(ascii: "H"):
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
            case UInt8(ascii: "V"):
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current)
            case UInt8(ascii: "C"):
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                nextControl = c2
                current = p
            case UInt8(ascii: "S"):
                let reflected = [UInt8(ascii: "C"), UInt8(ascii: "S")].contains(lastCommand) ? reflect(lastControl, around: current) : current
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: reflected, control2: c2)
                nextControl = c2
                current = p
            case UInt8(ascii: "Q"):
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                nextControl = c
                current = p
            case UInt8(ascii: "T"):
                let c = [UInt8(ascii: "Q"), UInt8(ascii: "T")].contains(lastCommand) ? reflect(lastControl, around: current) : current
                guard let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                nextControl = c
                current = p
            case UInt8(ascii: "A"):
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let largeArc = scanner.flag(), let sweep = scanner.flag(), let p = point() else { return path }
                addArc(to: path, from: current, to: p, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = p
            case UInt8(ascii: "Z"):
                path.closeSubpath()
                current = start
            default:
                return path
            }
            lastCommand = upper
            lastControl = nextControl
        }
        return path
    }

    private static func reflect(_ point: CGPoint?, around center: CGPoint) -> CGPoint {
        guard let point else { return center }
        return CGPoint(x: 2 * center.x - point.x, y: 2 * center.y - point.y)
    }

    /// SVG endpoint arc → center parameterization → cubic Bézier segments of at most 90°.
    private static func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coefficient = denominator == 0 ? 0 : sqrt(max(0, numerator / denominator))
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var theta = theta1
        func pointOnEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi, y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi, y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        for index in 0..<segments {
            let next = theta + step
            let start = pointOnEllipse(theta), end = index == segments - 1 ? p1 : pointOnEllipse(next)
            let d1 = derivative(theta), d2 = derivative(next)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + k * d1.x, y: start.y + k * d1.y),
                control2: CGPoint(x: end.x - k * d2.x, y: end.y - k * d2.y)
            )
            theta = next
        }
    }

    /// Tokenizer for SVG path data, including compact forms like `1.5.5`, `-1-2` and `a1 1 0 011 1`.
    private struct Tokens {
        let bytes: [UInt8]
        var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        private static func isSeparator(_ b: UInt8) -> Bool { b == 0x20 || b == 0x2C || b == 0x0A || b == 0x0D || b == 0x09 }

        /// Skips whitespace and commas. Returns false at the end of the data.
        mutating func skipSeparators() -> Bool {
            while index < bytes.count, Self.isSeparator(bytes[index]) { index += 1 }
            return index < bytes.count
        }

        mutating func command() -> UInt8? {
            guard skipSeparators() else { return nil }
            let b = bytes[index]
            let isLetter = (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
            guard isLetter, b != UInt8(ascii: "e"), b != UInt8(ascii: "E") else { return nil }
            index += 1
            return b
        }

        mutating func flag() -> Bool? {
            guard skipSeparators() else { return nil }
            let b = bytes[index]
            guard b == UInt8(ascii: "0") || b == UInt8(ascii: "1") else { return nil }
            index += 1
            return b == UInt8(ascii: "1")
        }

        mutating func number() -> CGFloat? {
            guard skipSeparators() else { return nil }
            let startIndex = index
            if bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
            var sawDot = false, sawDigit = false
            while index < bytes.count {
                let b = bytes[index]
                if b >= 48 && b <= 57 { sawDigit = true; index += 1 }
                else if b == UInt8(ascii: "."), !sawDot { sawDot = true; index += 1 }
                else if (b == UInt8(ascii: "e") || b == UInt8(ascii: "E")), sawDigit {
                    index += 1
                    if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
                    while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1 }
                    break
                } else { break }
            }
            guard sawDigit, let text = String(bytes: bytes[startIndex..<index], encoding: .ascii), let value = Double(text) else {
                index = startIndex
                return nil
            }
            return CGFloat(value)
        }
    }
}
