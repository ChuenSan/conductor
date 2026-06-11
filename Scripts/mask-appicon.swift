// 把满幅艺术图加工成 macOS 标准应用图标位图：
// 1024x1024 透明画布，居中 824x824 连续圆角矩形（radius≈185）蒙版内绘制图像。
// 用法：swift Scripts/mask-appicon.swift <input.png> <output.png> [cropOffsetX]
//   cropOffsetX：源图非正方形时方形裁剪窗口的 x 偏移（默认居中）。
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("用法: swift mask-appicon.swift <input.png> <output.png> [cropOffsetX]\n".data(using: .utf8)!)
    exit(1)
}

guard let source = NSImage(contentsOfFile: args[1]),
      var cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("读取输入失败：\(args[1])\n".data(using: .utf8)!)
    exit(1)
}

// 方形裁剪（可指定 x 偏移，y 居中）
let side = min(cg.width, cg.height)
let defaultX = (cg.width - side) / 2
let cropX = args.count >= 4 ? (Int(args[3]) ?? defaultX) : defaultX
let cropY = (cg.height - side) / 2
if let cropped = cg.cropping(to: CGRect(x: min(max(cropX, 0), cg.width - side),
                                        y: cropY, width: side, height: side)) {
    cg = cropped
}

let canvas = 1024
let content: CGFloat = 824           // Apple 图标网格：1024 画布内容区 824
let inset = (CGFloat(canvas) - content) / 2
let radius: CGFloat = 185.4          // Big Sur+ 圆角率（824 * 0.225）

let ctx = CGContext(
    data: nil, width: canvas, height: canvas,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let contentRect = CGRect(x: inset, y: inset, width: content, height: content)
let path = CGPath(roundedRect: contentRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(cg, in: contentRect)

// 顶部 1px 内描边高光，让边缘在深色桌面上更有质感
ctx.resetClip()
ctx.addPath(CGPath(roundedRect: contentRect.insetBy(dx: 0.5, dy: 0.5),
                   cornerWidth: radius - 0.5, cornerHeight: radius - 0.5, transform: nil))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
ctx.setLineWidth(1)
ctx.strokePath()

guard let out = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: out)
rep.size = NSSize(width: canvas, height: canvas)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: args[2]))
print("写出 \(args[2])（\(canvas)x\(canvas)，内容 \(Int(content))，radius \(radius)）")
