// Génère l'icône de Sillage : tuile dégradée corail → rose, un fil vertical (la journée) ponctué de
// points et de blocs d'activités de durées différentes.
// Usage : swift tools/make_icon.swift <dossier-de-sortie.iconset>
import AppKit
import CoreGraphics

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                         CGFloat(hex & 0xFF) / 255, a])!
}

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let inset = s * 0.055
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tile = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.014), blur: s * 0.035, color: CGColor(gray: 0, alpha: 0.4))
    ctx.addPath(tile); ctx.setFillColor(rgb(0xD9366B)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [rgb(0xFF9A55), rgb(0xE8455F), rgb(0xB82A78)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // x, y dans un repère [0,1] du carré, Y vers le haut
    func X(_ v: CGFloat) -> CGFloat { rect.minX + v * rect.width }
    func Y(_ v: CGFloat) -> CGFloat { rect.minY + v * rect.height }

    // le fil
    ctx.setFillColor(rgb(0xFFFFFF, 0.55))
    ctx.addPath(CGPath(roundedRect: CGRect(x: X(0.25), y: Y(0.13), width: s * 0.026, height: rect.height * 0.74),
                       cornerWidth: s * 0.013, cornerHeight: s * 0.013, transform: nil)); ctx.fillPath()

    // points + blocs (haut → bas)
    let items: [(y: CGFloat, h: CGFloat, w: CGFloat, a: CGFloat)] = [
        (0.78, 0.10, 0.46, 1.0), (0.50, 0.20, 0.34, 0.88), (0.22, 0.10, 0.40, 0.72),
    ]
    for it in items {
        let cy = Y(it.y)
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: X(0.25) + s * 0.013 - s * 0.042, y: cy - s * 0.042 + 0, width: s * 0.084, height: s * 0.084))
        let r = CGRect(x: X(0.38), y: cy - rect.height * it.h / 2, width: rect.width * it.w, height: rect.height * it.h)
        ctx.setFillColor(rgb(0xFFFFFF, it.a))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)); ctx.fillPath()
    }
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print(out.path)
