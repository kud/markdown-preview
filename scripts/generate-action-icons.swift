#!/usr/bin/env swift
//
// Regenerates the Finder Quick Action icons in ExportMarkdownAction. They sit at
// the root of that synchronized folder so they land directly in each .appex's
// Contents/Resources, and each target names its own via FINDER_ACTION_ICON_NAME
// (wired to CFBundleIconName / NSExtensionServiceToolbarIconFile in Info.plist).
//
//   swift scripts/generate-action-icons.swift ExportMarkdownAction
//
// Matching Apple's built-in actions
// --------------------------------
// Login Items & Extensions draws each action's icon *as authored* — it does not
// composite a plate. Apple's built-ins (Create PDF, Trim, Convert Image, Remove
// Background) and third-party ones alike ship the rounded plate inside their own
// artwork, which is why a bare glyph renders plate-less and undersized.
//
// The numbers below were measured off Apple's own Create PDF icon as rendered in
// that list, so ours line up 1:1:
//
//   plate        26x26pt, corner radius 8pt, vertical gradient #B4B4B9 -> #8E8E93
//   glyph        white, fitted to a centred 14pt box
//   canvas       32x32pt, plate centred — the list draws at natural size and
//                does not upscale, so the canvas has to be the full slot
//
// The plate is not a flat fill. Sampling a column down Apple's tiles gives ~#B4B4B9
// at the top falling to systemGray #8E8E93 about 60% of the way down and staying
// there — a subtle top-lit sheen. Create PDF and Convert Image measure identically,
// so it is a system treatment rather than per-icon artwork. A flat systemGray plate
// is noticeably duller side by side.
//
// When comparing against a screen capture, convert samples to sRGB first. Raw
// bitmap components come back in the display's space, where Apple's #8E8E93 reads
// as #7B7B81 — that gap is a colour-space artifact, not the list darkening icons.
//
// The glyphs themselves are Apple's real SF Symbol outlines, read from
// NSSymbolImageRep's `outlinePath` rather than redrawn by hand.
//
// The filenames deliberately avoid a "Template" suffix: NSImage would then treat
// them as template images and flatten the plate and glyph into one solid mask.
//
// Output is PNG at 1x/2x rather than a vector PDF: a fill in a CGPDFContext is
// written untagged, whereas PNG carries an explicit sRGB profile. 1x/2x only —
// macOS has no 3x displays, and tiffutil mis-tags a third rep's point size.

import AppKit

let specs: [(file: String, symbol: String)] = [
  // `doc` is the same page-with-folded-corner silhouette Finder uses for Create PDF.
  ("CreatePDFActionIcon",      "doc"),
  // `photo` matches Finder's Convert Image.
  ("CreatePNGActionIcon",      "photo"),
  ("CreateHTMLActionIcon",     "chevron.left.forwardslash.chevron.right"),
  // Stays in the document family alongside Create PDF rather than the busier
  // square.and.arrow.up, which visually merges at this size.
  ("ExportMarkdownActionIcon", "arrow.up.doc"),
]

let canvas: CGFloat = 32
let plateSide: CGFloat = 26
let plateRadius: CGFloat = 8
let glyphBox: CGFloat = 14
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
// Bottom is systemGray in light appearance; the top is lifted to match Apple's
// sheen. Greys either way, as Apple uses, so the one static asset reads correctly
// against both the light and dark extension list.
let plateBottom = CGColor(colorSpace: sRGB,
                          components: [0x8E/255.0, 0x8E/255.0, 0x93/255.0, 1])!
let plateTop = CGColor(colorSpace: sRGB,
                       components: [0xB4/255.0, 0xB4/255.0, 0xB9/255.0, 1])!
// Stops run bottom-to-top: flat systemGray across the lower 38%, then the ramp.
let plateGradient = CGGradient(colorsSpace: sRGB,
                               colors: [plateBottom, plateBottom, plateTop] as CFArray,
                               locations: [0, 0.38, 1])!

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(
    "usage: generate-action-icons.swift <output-dir>\n".data(using: .utf8)!)
  exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

/// Apple's SF Symbol outline for `symbol`, in unflipped coordinates.
func outline(of symbol: String) -> NSBezierPath {
  guard let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
          .withSymbolConfiguration(.init(pointSize: 256, weight: .regular)),
        let rep = sym.representations.first,
        let raw = rep.value(forKey: "outlinePath") as? NSBezierPath
  else { fatalError("no outline path for SF Symbol \(symbol)") }
  // `outlinePath` is handed back in flipped (top-left origin) coordinates.
  let path = raw.copy() as! NSBezierPath
  var flip = AffineTransform(scaleByX: 1, byY: -1)
  flip.append(AffineTransform(translationByX: 0, byY: raw.bounds.maxY + raw.bounds.minY))
  path.transform(using: flip)
  return path
}

for spec in specs {
  let glyph = outline(of: spec.symbol)
  let b = glyph.bounds
  // Fit the glyph into a centred box, aspect preserved, the way Apple's sit.
  let scale = min(glyphBox / b.width, glyphBox / b.height)
  var fit = AffineTransform(scaleByX: scale, byY: scale)
  fit.append(AffineTransform(translationByX: (canvas - b.width * scale) / 2 - b.minX * scale,
                             byY: (canvas - b.height * scale) / 2 - b.minY * scale))
  glyph.transform(using: fit)

  let plate = NSRect(x: (canvas - plateSide) / 2, y: (canvas - plateSide) / 2,
                     width: plateSide, height: plateSide)
  let plateShape = NSBezierPath(roundedRect: plate,
                                xRadius: plateRadius, yRadius: plateRadius).cgPath

  for scaleFactor in [1, 2] {
    let px = Int(canvas) * scaleFactor
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(scaleFactor), y: CGFloat(scaleFactor))
    ctx.setShouldAntialias(true)

    ctx.saveGState()
    ctx.addPath(plateShape)
    ctx.clip()
    ctx.drawLinearGradient(plateGradient,
                           start: CGPoint(x: plate.midX, y: plate.minY),
                           end: CGPoint(x: plate.midX, y: plate.maxY),
                           options: [])
    ctx.restoreGState()

    ctx.setFillColor(CGColor(colorSpace: sRGB, components: [1, 1, 1, 1])!)
    ctx.addPath(glyph.cgPath)
    ctx.fillPath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: canvas, height: canvas)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      fatalError("could not encode \(spec.file)@\(scaleFactor)x")
    }
    let suffix = scaleFactor == 1 ? "" : "@\(scaleFactor)x"
    try png.write(to: outDir.appendingPathComponent("\(spec.file)\(suffix).png"))
  }
  print("\(spec.file).png (1x/2x)  <-  \(spec.symbol)")
}
