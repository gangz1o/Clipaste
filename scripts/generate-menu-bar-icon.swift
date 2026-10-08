import AppKit
import CoreGraphics

// Run with: swift scripts/generate-menu-bar-icon.swift <output.pdf> [preview.png]
// A vector template keeps the menu-bar mark crisp at every display scale.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
var page = CGRect(x: 0, y: 0, width: 18, height: 18)
let body = CGMutablePath()
body.move(to: CGPoint(x: 3, y: 4.7))
body.addLine(to: CGPoint(x: 3, y: 14.8))
body.addQuadCurve(to: CGPoint(x: 5.2, y: 17), control: CGPoint(x: 3, y: 17))
body.addLine(to: CGPoint(x: 10.7, y: 17))
body.addCurve(to: CGPoint(x: 15.5, y: 12), control1: CGPoint(x: 13.8, y: 17), control2: CGPoint(x: 15.5, y: 15))
body.addCurve(to: CGPoint(x: 10.7, y: 7), control1: CGPoint(x: 15.5, y: 9), control2: CGPoint(x: 13.8, y: 7))
body.addLine(to: CGPoint(x: 7, y: 7))
body.addLine(to: CGPoint(x: 3, y: 4.7))
body.closeSubpath()
body.addRoundedRect(in: CGRect(x: 7, y: 10, width: 4.7, height: 4), cornerWidth: 1.2, cornerHeight: 1.2)

let fold = CGMutablePath()
fold.move(to: CGPoint(x: 3, y: 3.6))
fold.addLine(to: CGPoint(x: 7, y: 5.9))
fold.addLine(to: CGPoint(x: 7, y: 1.6))
fold.addQuadCurve(to: CGPoint(x: 6.3, y: 1.2), control: CGPoint(x: 7, y: 1))
fold.addLine(to: CGPoint(x: 3.6, y: 2.8))
fold.addQuadCurve(to: CGPoint(x: 3, y: 3.6), control: CGPoint(x: 3, y: 3.1))
fold.closeSubpath()

func drawMark(in context: CGContext, color: CGColor) {
    context.setFillColor(color)
    context.addPath(body)
    context.drawPath(using: .eoFill)
    context.addPath(fold)
    context.fillPath()
}

let pdf = CGContext(output as CFURL, mediaBox: &page, nil)!
pdf.beginPDFPage(nil)
drawMark(in: pdf, color: CGColor(gray: 0, alpha: 1))
pdf.endPDFPage()
pdf.closePDF()
print("Generated an 18 pt monochrome vector template: \(output.path)")

if CommandLine.arguments.count > 2 {
    let preview = NSImage(size: NSSize(width: 460, height: 180))
    preview.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    for (index, background) in [CGFloat(0.94), CGFloat(0.12)].enumerated() {
        let offset = CGFloat(index) * 230
        context.setFillColor(CGColor(gray: background, alpha: 1))
        context.fill(CGRect(x: offset, y: 0, width: 230, height: 180))
        for (x, y, scale) in [(CGFloat(30), CGFloat(80), CGFloat(1)), (CGFloat(95), CGFloat(54), CGFloat(4))] {
            context.saveGState()
            context.translateBy(x: offset + x, y: y)
            context.scaleBy(x: scale, y: scale)
            drawMark(in: context, color: CGColor(gray: index == 0 ? 0.1 : 0.95, alpha: 1))
            context.restoreGState()
        }
    }
    preview.unlockFocus()
    let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
