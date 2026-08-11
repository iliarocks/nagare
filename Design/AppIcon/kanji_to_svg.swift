import AppKit
import CoreText

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: kanji_to_svg <font-name> <fill-color> <output-path>\n", stderr)
    exit(2)
}

let fontName = CommandLine.arguments[1]
let fillColor = CommandLine.arguments[2]
let outputPath = CommandLine.arguments[3]
let canvasSize: CGFloat = 1024
let targetSize: CGFloat = 690

let font = CTFontCreateWithName(fontName as CFString, 1000, nil)
var character = Array("流".utf16)[0]
var glyph = CGGlyph()

guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
      let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) else {
    fputs("Could not create the 流 glyph with \(fontName)\n", stderr)
    exit(1)
}

let bounds = glyphPath.boundingBoxOfPath
let scale = min(targetSize / bounds.width, targetSize / bounds.height)
let placedWidth = bounds.width * scale
let placedHeight = bounds.height * scale
let offsetX = (canvasSize - placedWidth) / 2 - bounds.minX * scale
let offsetY = (canvasSize - placedHeight) / 2 - bounds.minY * scale

func point(_ source: CGPoint) -> CGPoint {
    CGPoint(
        x: offsetX + source.x * scale,
        y: canvasSize - (offsetY + source.y * scale)
    )
}

func number(_ value: CGFloat) -> String {
    String(format: "%.2f", value)
}

var commands: [String] = []
glyphPath.applyWithBlock { pointer in
    let element = pointer.pointee
    switch element.type {
    case .moveToPoint:
        let p = point(element.points[0])
        commands.append("M\(number(p.x)) \(number(p.y))")
    case .addLineToPoint:
        let p = point(element.points[0])
        commands.append("L\(number(p.x)) \(number(p.y))")
    case .addQuadCurveToPoint:
        let control = point(element.points[0])
        let end = point(element.points[1])
        commands.append(
            "Q\(number(control.x)) \(number(control.y)) \(number(end.x)) \(number(end.y))"
        )
    case .addCurveToPoint:
        let control1 = point(element.points[0])
        let control2 = point(element.points[1])
        let end = point(element.points[2])
        commands.append(
            "C\(number(control1.x)) \(number(control1.y)) " +
            "\(number(control2.x)) \(number(control2.y)) " +
            "\(number(end.x)) \(number(end.y))"
        )
    case .closeSubpath:
        commands.append("Z")
    @unknown default:
        break
    }
}

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <path d="\(commands.joined(separator: " "))" fill="\(fillColor)"/>
</svg>
"""

try svg.write(toFile: outputPath, atomically: true, encoding: .utf8)
