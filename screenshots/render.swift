import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Rebuild App Store exports from originals/: swift screenshots/render.swift [iPhone|Mac]
// iPhone originals must be 1206 × 2622; Mac originals are window captures.
// Apple's unmodified iPhone 17 White bezel: https://developer.apple.com/design/resources/#product-bezels
// Source: https://devimages-cdn.apple.com/design/resources/download/Bezel-iPhone-17.dmg
// See the adjacent Apple-License.rtf for its license.
let root = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent()
let platforms = CommandLine.arguments.count > 1 ? [CommandLine.arguments[1]] : ["iPhone", "Mac"]
precondition(platforms.allSatisfy { ["iPhone", "Mac"].contains($0) }, "Expected iPhone or Mac")
let pages = ["01-today", "02-upcoming", "03-project", "04-task-notes"]
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
let appleFrame = loadImage(root.appendingPathComponent("iPhone-17.png"))
let appleScreenMask = screenMask(appleFrame)

func phone(_ c: CGContext, _ raw: CGImage) {
    let w = CGFloat(c.width); let h = CGFloat(c.height)
    let outerWidth = w * 0.89
    let scale = outerWidth / CGFloat(appleFrame.width)
    let outerHeight = CGFloat(appleFrame.height) * scale
    let x = (w - outerWidth) / 2
    let y = (h - outerHeight) / 2
    precondition(y >= 0 && y + outerHeight <= h, "Device extends outside the canvas")
    precondition(raw.width == 1206 && raw.height == 2622, "Screenshot must match the official device screen")
    c.saveGState()
    c.translateBy(x: x, y: y + outerHeight); c.scaleBy(x: scale, y: -scale)
    c.clip(to: CGRect(x: 0, y: 0, width: appleFrame.width, height: appleFrame.height), mask: appleScreenMask)
    c.draw(raw, in: CGRect(x: 72, y: appleFrame.height - 69 - 2622, width: 1206, height: 2622))
    c.restoreGState()
    drawImage(c, appleFrame, CGRect(x: x, y: y, width: outerWidth, height: outerHeight))
}
func mac(_ c: CGContext, _ raw: CGImage) {
    let w = CGFloat(c.width); let h = CGFloat(c.height)
    let ratio = CGFloat(raw.height) / CGFloat(raw.width)
    let windowWidth = min(w * 0.85, h * 0.85 / ratio)
    let windowHeight = windowWidth * ratio
    let rect = CGRect(x: (w - windowWidth) / 2, y: (h - windowHeight) / 2, width: windowWidth, height: windowHeight)
    let radius = windowWidth * 0.021
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 18), blur: 45, color: NSColor.black.withAlphaComponent(0.20).cgColor)
    fill(c, rect, radius, "#FFFFFF"); c.restoreGState()
    c.saveGState(); c.addPath(rounded(rect, radius)); c.clip(); drawImage(c, raw, rect); c.restoreGState()

}
for platform in platforms {
    let isMac = platform == "Mac"
    let width = isMac ? 2880 : 1320
    let height = isMac ? 1800 : 2868
    for page in pages {
        let rawURL = root.appendingPathComponent("originals/\(platform)/\(page).png")
        let output = root.appendingPathComponent("app-store/\(platform)/\(page).png")
        let c = canvas(width, height)
        fill(c, CGRect(x: 0, y: 0, width: width, height: height), 0, "#607D8B")
        if isMac { mac(c, loadImage(rawURL)) } else { phone(c, loadImage(rawURL)) }
        try save(c, output)
    }
    print("Rendered \(platform): \(pages.count) pages")
}
