#!/usr/bin/env swift
// Generates the rede app icon set + menu bar template icons.
// Same visual language as the Blitztext original (black rounded square, white mark) with the
// rede speech motif: a white speech bubble carrying three rounded "speech" bars, the middle one
// in the warm rede accent (coral). Usage:
//   swift generate-icons.swift <output-dir>
// Writes: rede.iconset/ (for iconutil), menubar_icon.png, menubar_icon@2x.png

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
  FileHandle.standardError.write(Data("Usage: generate-icons.swift <output-dir>\n".utf8))
  exit(1)
}
let outputDir = URL(fileURLWithPath: args[1], isDirectory: true)
let iconsetDir = outputDir.appendingPathComponent("rede.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// rede brand accent (warm coral) — see DESIGN.md (rede edition).
let accent = CGColor(red: 1.00, green: 0.36, blue: 0.30, alpha: 1.0)
let black = CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0)
let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

func makeContext(size: Int) -> CGContext {
  let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  ctx.interpolationQuality = .high
  return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) {
  let image = ctx.makeImage()!
  let rep = NSBitmapImageRep(cgImage: image)
  rep.size = NSSize(width: ctx.width, height: ctx.height)
  let data = rep.representation(using: .png, properties: [:])!
  try! data.write(to: url)
}

/// Rounded "speech bars" inside a bubble: the mark reads as someone speaking.
/// All geometry in unit coordinates of the artwork square (0…1), drawn bottom-up (CG coords).
/// `punchColor` paints the non-accent bars (e.g. the icon's black background colour);
/// nil punches them to full transparency (correct for the monochrome template icon).
func drawMark(
  in ctx: CGContext, artworkRect: CGRect, barColor: CGColor, accentColor: CGColor?,
  punchColor: CGColor?
) {
  let w = artworkRect.width

  // Speech bubble body: rounded rect occupying the upper ~62% of the artwork, plus a tail.
  let bubble = CGRect(
    x: artworkRect.minX + 0.16 * w,
    y: artworkRect.minY + 0.34 * w,
    width: 0.68 * w,
    height: 0.46 * w
  )
  let bubbleRadius = 0.115 * w
  let bubblePath = CGMutablePath()
  bubblePath.addRoundedRect(
    in: bubble, cornerWidth: bubbleRadius, cornerHeight: bubbleRadius)

  // Tail: top edge sits inside the bubble's full-width zone (x past the corner-radius band,
  // y just below the lowest bar) so the white union is seamless and never crosses a bar.
  let tail = CGMutablePath()
  tail.move(to: CGPoint(x: bubble.minX + 0.14 * w, y: bubble.minY + 0.115 * w))
  tail.addLine(to: CGPoint(x: bubble.minX + 0.33 * w, y: bubble.minY + 0.115 * w))
  tail.addLine(to: CGPoint(x: bubble.minX + 0.095 * w, y: artworkRect.minY + 0.16 * w))
  tail.closeSubpath()

  // Fill bubble and tail SEPARATELY: one combined fillPath XORs their overlap away
  // (opposite path windings), punching a hole exactly where the tail enters the bubble.
  ctx.setFillColor(barColor)
  ctx.addPath(bubblePath)
  ctx.fillPath()
  ctx.addPath(tail)
  ctx.fillPath()

  // Three speech bars inside the bubble — middle one accent-colored, the others punched
  // (painted in punchColor, or true transparency for the template variant). CG coords are
  // bottom-up: topBarY is the BOTTOM edge of the topmost bar; lower bars subtract the gap.
  // Lowest bar bottom = bubble.maxY - 0.335w = bubble.minY + 0.125w → clears the tail (0.115w).
  let barHeight = 0.062 * w
  let barRadius = barHeight / 2
  let barX = bubble.minX + 0.10 * w
  let topBarY = bubble.maxY - 0.125 * w
  let gap = 0.105 * w
  let widths: [CGFloat] = [0.46 * w, 0.34 * w, 0.40 * w]

  for (index, barWidth) in widths.enumerated() {
    let rect = CGRect(
      x: barX, y: topBarY - CGFloat(index) * gap, width: barWidth, height: barHeight)
    let path = CGPath(
      roundedRect: rect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
    if index == 1, let accentColor {
      ctx.setFillColor(accentColor)
      ctx.addPath(path)
      ctx.fillPath()
    } else if let punchColor {
      ctx.setFillColor(punchColor)
      ctx.addPath(path)
      ctx.fillPath()
    } else {
      // True punch-through for the monochrome template icon.
      ctx.setBlendMode(.clear)
      ctx.addPath(path)
      ctx.fillPath()
      ctx.setBlendMode(.normal)
    }
  }
}

/// Full app icon: black rounded square (Big-Sur-style margin) + white bubble mark.
func drawAppIcon(size: Int) -> CGContext {
  let ctx = makeContext(size: size)
  let s = CGFloat(size)

  // Standard macOS icon grid: artwork square ~80.4% of canvas, centered (transparent margin).
  let artworkSide = 0.804 * s
  let artworkRect = CGRect(
    x: (s - artworkSide) / 2, y: (s - artworkSide) / 2, width: artworkSide, height: artworkSide)
  let cornerRadius = 0.225 * artworkSide

  ctx.setFillColor(black)
  ctx.addPath(
    CGPath(
      roundedRect: artworkRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
      transform: nil))
  ctx.fillPath()

  drawMark(
    in: ctx, artworkRect: artworkRect, barColor: white, accentColor: accent, punchColor: black)
  return ctx
}

/// Menu bar template icon: monochrome black mark on transparent (macOS tints it).
func drawMenuBarIcon(size: Int) -> CGContext {
  let ctx = makeContext(size: size)
  let s = CGFloat(size)
  let artworkRect = CGRect(x: 0, y: 0, width: s, height: s)
  // Template icons: solid black; bars punch through to transparent, no accent.
  drawMark(in: ctx, artworkRect: artworkRect, barColor: black, accentColor: nil, punchColor: nil)
  return ctx
}

// App iconset (all required sizes for iconutil).
let iconSizes: [(name: String, px: Int)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for spec in iconSizes {
  let ctx = drawAppIcon(size: spec.px)
  writePNG(ctx, to: iconsetDir.appendingPathComponent("\(spec.name).png"))
}

// Menu bar template (18pt @1x/@2x — matches the existing menubar_icon resource).
writePNG(drawMenuBarIcon(size: 18), to: outputDir.appendingPathComponent("menubar_icon.png"))
writePNG(drawMenuBarIcon(size: 36), to: outputDir.appendingPathComponent("menubar_icon@2x.png"))

// 1024 master for Assets.xcassets / AppIcon.icon layer reuse.
writePNG(drawAppIcon(size: 1024), to: outputDir.appendingPathComponent("rede-icon-1024.png"))

print("Icons written to \(outputDir.path)")
print("Next: iconutil -c icns \(iconsetDir.path) -o AppIcon.icns")
