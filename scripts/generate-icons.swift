#!/usr/bin/env swift
// Generates the rede app icon set + menu bar template icons — "electric" direction.
// Electric-violet rounded square, white speech bubble (tail bottom-left) carrying an
// acid-lime voice waveform. Usage:
//   swift generate-icons.swift <output-dir>
// Writes: rede.iconset/ (for iconutil), menubar_icon.png, menubar_icon@2x.png,
//         rede-icon-1024.png (asset-catalog master).

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

// rede brand palette (DESIGN.md, rede edition).
let violet = CGColor(red: 0.431, green: 0.337, blue: 0.973, alpha: 1.0)  // #6E56F8
let lime = CGColor(red: 0.800, green: 1.000, blue: 0.102, alpha: 1.0)  // #CCFF1A
let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
let ink = CGColor(red: 0.055, green: 0.043, blue: 0.102, alpha: 1.0)  // #0E0B1A
let mist = CGColor(red: 0.949, green: 0.941, blue: 0.984, alpha: 1.0)  // #F2F0FB

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

/// A horizontal voice waveform: alternating quad-curve humps across [x0, x1] centred on `cy`.
/// `humps` = number of half-waves; the first one goes UP (screen-up = +y in CG bottom-up coords).
func wavePath(x0: CGFloat, x1: CGFloat, cy: CGFloat, amplitude: CGFloat, humps: Int) -> CGPath {
  let path = CGMutablePath()
  path.move(to: CGPoint(x: x0, y: cy))
  let segment = (x1 - x0) / CGFloat(humps)
  for index in 0..<humps {
    let startX = x0 + CGFloat(index) * segment
    let endX = startX + segment
    let controlY = cy + (index % 2 == 0 ? amplitude : -amplitude)
    path.addQuadCurve(
      to: CGPoint(x: endX, y: cy),
      control: CGPoint(x: (startX + endX) / 2, y: controlY))
  }
  return path
}

/// Speech bubble (rounded body + tail bottom-left) carrying a voice waveform.
/// `bubbleColor` fills the bubble; `waveColor` strokes the wave (nil = punch the wave to
/// transparency, used for the monochrome menu bar template).
func drawMark(in ctx: CGContext, artworkRect: CGRect, bubbleColor: CGColor, waveColor: CGColor?) {
  let w = artworkRect.width

  // Bigger mark, less empty margin inside the rounded square (user feedback).
  let bubble = CGRect(
    x: artworkRect.minX + 0.10 * w,
    y: artworkRect.minY + 0.30 * w,
    width: 0.80 * w,
    height: 0.56 * w
  )
  let bubbleRadius = 0.155 * w
  let bubblePath = CGPath(
    roundedRect: bubble, cornerWidth: bubbleRadius, cornerHeight: bubbleRadius, transform: nil)

  // Tail: top edge inside the bubble's full-width zone so the union is seamless.
  let tail = CGMutablePath()
  tail.move(to: CGPoint(x: bubble.minX + 0.16 * w, y: bubble.minY + 0.10 * w))
  tail.addLine(to: CGPoint(x: bubble.minX + 0.38 * w, y: bubble.minY + 0.10 * w))
  tail.addLine(to: CGPoint(x: bubble.minX + 0.07 * w, y: artworkRect.minY + 0.12 * w))
  tail.closeSubpath()

  // Fill bubble and tail in SEPARATE fillPath calls (a single combined fill would XOR the
  // overlap away due to opposite windings, punching a hole where the tail meets the bubble).
  ctx.setFillColor(bubbleColor)
  ctx.addPath(bubblePath)
  ctx.fillPath()
  ctx.addPath(tail)
  ctx.fillPath()

  // Voice waveform across the bubble.
  let wave = wavePath(
    x0: bubble.minX + 0.17 * w,
    x1: bubble.maxX - 0.17 * w,
    cy: bubble.midY + 0.03 * w,
    amplitude: 0.10 * w,
    humps: 3)
  let lineWidth = 0.06 * w

  if let waveColor {
    ctx.setStrokeColor(waveColor)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.addPath(wave)
    ctx.strokePath()
  } else {
    // Punch the wave to transparency for the template icon.
    ctx.setBlendMode(.clear)
    ctx.setStrokeColor(white)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.addPath(wave)
    ctx.strokePath()
    ctx.setBlendMode(.normal)
  }
}

/// Full app icon: soft mist rounded square + violet bubble + lime wave (the "soft / hell" direction).
func drawAppIcon(size: Int) -> CGContext {
  let ctx = makeContext(size: size)
  let s = CGFloat(size)

  // Standard macOS icon grid: artwork square ~80.4% of canvas, centered (transparent margin).
  let artworkSide = 0.804 * s
  let artworkRect = CGRect(
    x: (s - artworkSide) / 2, y: (s - artworkSide) / 2, width: artworkSide, height: artworkSide)
  let cornerRadius = 0.225 * artworkSide

  ctx.setFillColor(mist)
  ctx.addPath(
    CGPath(
      roundedRect: artworkRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
      transform: nil))
  ctx.fillPath()

  drawMark(in: ctx, artworkRect: artworkRect, bubbleColor: violet, waveColor: lime)
  return ctx
}

/// Menu bar template icon: monochrome black bubble on transparent (macOS tints it); the wave is
/// punched to transparency so the silhouette reads as "speech".
func drawMenuBarIcon(size: Int) -> CGContext {
  let ctx = makeContext(size: size)
  let s = CGFloat(size)
  let artworkRect = CGRect(x: 0, y: 0, width: s, height: s)
  drawMark(in: ctx, artworkRect: artworkRect, bubbleColor: ink, waveColor: nil)
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
