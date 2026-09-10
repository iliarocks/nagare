import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Deterministic composition: the app pixels come exclusively from originals/.
// Usage: swift render.swift [path/to/layout.json]
struct Layout: Decodable {
    let app: String
    let background: String
    let phone: Phone
    let mac: Mac?
    let sets: [PageSet]
}
struct Phone: Decodable {
    let width: Int, height: Int
    let deviceWidth: Double
    let frame: Frame
}
struct Frame: Decodable {
    let asset: String
    let screenX: Int, screenY: Int, screenWidth: Int, screenHeight: Int
}
struct Mac: Decodable {
    let width: Int, height: Int
    let maxWindowWidth: Double, maxWindowHeight: Double
}
struct PageSet: Decodable { let platform: String; let pages: [String] }
let configURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "layout.json").standardizedFileURL
let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: configURL))
let design = configURL.deletingLastPathComponent()
let root = design.deletingLastPathComponent()
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: String) -> CGColor {
    let n = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16)!
    return CGColor(colorSpace: space, components: [CGFloat((n >> 16) & 255) / 255, CGFloat((n >> 8) & 255) / 255, CGFloat(n & 255) / 255, 1])!
}
func canvas(_ width: Int, _ height: Int) -> CGContext {
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(height)); c.scaleBy(x: 1, y: -1)
    c.interpolationQuality = .high
    return c
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, _ hex: String) {
    c.addPath(rounded(r, radius)); c.setFillColor(color(hex)); c.fillPath()
}
func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read \(url.path)") }
    return image
}
func drawImage(_ c: CGContext, _ image: CGImage, _ rect: CGRect) {
    c.saveGState(); c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: 1, y: -1)
    c.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height)); c.restoreGState()
}
func save(_ c: CGContext, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, c.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(url.path)") }
}
// Trace Apple's enclosed transparent screen opening, including the actual
// corner shape and camera housing. The original Apple PNG stays unmodified.
func screenMask(_ image: CGImage) -> CGImage {
    let width = image.width, height = image.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    rgba.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var mask = [UInt8](repeating: 0, count: width * height)
    let seed = (height / 2) * width + width / 2
    precondition(rgba[seed * 4 + 3] == 0, "Apple frame has no transparent screen")
    var queue = [seed], head = 0
    mask[seed] = 255
    while head < queue.count {
        let index = queue[head]; head += 1
        let x = index % width, y = index / width
        for neighbor in [x > 0 ? index - 1 : -1, x + 1 < width ? index + 1 : -1, y > 0 ? index - width : -1, y + 1 < height ? index + width : -1] {
            if neighbor >= 0 && mask[neighbor] == 0 && rgba[neighbor * 4 + 3] < 255 {
                mask[neighbor] = 255; queue.append(neighbor)
            }
        }
    }
    precondition(mask[0] == 0, "Screen mask leaked into exterior transparency")
    let data = Data(mask) as CFData
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}
let appleFrame = loadImage(design.appendingPathComponent(layout.phone.frame.asset))
let appleScreenMask = screenMask(appleFrame)

func phone(_ c: CGContext, _ raw: CGImage) {
    let p = layout.phone; let w = CGFloat(p.width); let h = CGFloat(p.height)
    let outerWidth = w * p.deviceWidth
    let scale = outerWidth / CGFloat(appleFrame.width)
    let outerHeight = CGFloat(appleFrame.height) * scale
    let x = (w - outerWidth) / 2
    let y = (h - outerHeight) / 2
    precondition(y >= 0 && y + outerHeight <= h, "Device extends outside the canvas")
    let frame = p.frame
    precondition(raw.width == frame.screenWidth && raw.height == frame.screenHeight, "Screenshot must match the official device screen")
    c.saveGState()
    c.translateBy(x: x, y: y + outerHeight); c.scaleBy(x: scale, y: -scale)
    c.clip(to: CGRect(x: 0, y: 0, width: appleFrame.width, height: appleFrame.height), mask: appleScreenMask)
    c.draw(raw, in: CGRect(x: frame.screenX, y: appleFrame.height - frame.screenY - frame.screenHeight, width: frame.screenWidth, height: frame.screenHeight))
    c.restoreGState()
    drawImage(c, appleFrame, CGRect(x: x, y: y, width: outerWidth, height: outerHeight))
}
func mac(_ c: CGContext, _ raw: CGImage) {
    let p = layout.mac!; let w = CGFloat(p.width); let h = CGFloat(p.height)
    let ratio = CGFloat(raw.height) / CGFloat(raw.width)
    let windowWidth = min(w * p.maxWindowWidth, h * p.maxWindowHeight / ratio)
    let windowHeight = windowWidth * ratio
    let rect = CGRect(x: (w - windowWidth) / 2, y: (h - windowHeight) / 2, width: windowWidth, height: windowHeight)
    let radius = windowWidth * 0.021
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 18), blur: 45, color: NSColor.black.withAlphaComponent(0.20).cgColor)
    fill(c, rect, radius, "#FFFFFF"); c.restoreGState()
    c.saveGState(); c.addPath(rounded(rect, radius)); c.clip(); drawImage(c, raw, rect); c.restoreGState()

}
for set in layout.sets where CommandLine.arguments.count < 3 || set.platform == CommandLine.arguments[2] {
    let isMac = set.platform == "Mac"
    let width = isMac ? layout.mac!.width : layout.phone.width
    let height = isMac ? layout.mac!.height : layout.phone.height
    for page in set.pages {
        let rawURL = root.appendingPathComponent("originals/\(set.platform)/\(page).png")
        let output = root.appendingPathComponent("app-store/\(set.platform)/\(page).png")
        let c = canvas(width, height)
        fill(c, CGRect(x: 0, y: 0, width: width, height: height), 0, layout.background)
        if isMac { mac(c, loadImage(rawURL)) } else { phone(c, loadImage(rawURL)) }
        try save(c, output)
    }
    // A separate contact sheet for review; never mixed with upload-ready pages.
    let thumbWidth = isMac ? 760 : 330
    let thumbHeight = Int(Double(thumbWidth) * Double(height) / Double(width))
    let gap = 24, margin = 32
    let columns = isMac ? 2 : 4, rows = isMac ? 2 : 1
    let sheet = canvas(margin * 2 + columns * thumbWidth + (columns - 1) * gap, margin * 2 + rows * thumbHeight + (rows - 1) * gap)
    fill(sheet, CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height), 0, "#F0F1F2")
    for (index, page) in set.pages.enumerated() {
        let image = loadImage(root.appendingPathComponent("app-store/\(set.platform)/\(page).png"))
        drawImage(sheet, image, CGRect(x: margin + (index % columns) * (thumbWidth + gap), y: margin + (index / columns) * (thumbHeight + gap), width: thumbWidth, height: thumbHeight))
    }
    try save(sheet, design.appendingPathComponent("Previews/\(layout.app)-\(set.platform).png"))
    print("Rendered \(layout.app) \(set.platform): \(set.pages.count) pages")
}
