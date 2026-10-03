import AppKit
// Scale each screenshot to 1284 wide, then crop evenly top and bottom to 2778 tall (no stretching).
let (src, dst) = (CommandLine.arguments[1], CommandLine.arguments[2])
let targetW = 1284, targetH = 2778
try? FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
for name in try! FileManager.default.contentsOfDirectory(atPath: src).sorted() where name.hasSuffix(".png") {
    let image = NSImage(contentsOfFile: src + "/" + name)!
    let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let scale = Double(targetW) / Double(cg.width)
    let scaledH = Double(cg.height) * scale
    let ctx = CGContext(data: nil, width: targetW, height: targetH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    let y = (Double(targetH) - scaledH) / 2
    ctx.draw(cg, in: CGRect(x: 0, y: y, width: Double(targetW), height: scaledH))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst + "/" + name))
    print(name)
}
