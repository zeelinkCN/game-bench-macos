#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Games", isDirectory: true)
let catalogURL = root.appendingPathComponent("catalog.json")
let data = try Data(contentsOf: catalogURL)
guard var games = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
    fatalError("Invalid catalog")
}
let directory = root.appendingPathComponent("covers/fallback", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var made = 0

for index in games.indices where games[index]["cover"] == nil {
    guard let title = games[index]["title"] as? String, let hash = games[index]["sha256"] as? String else { continue }
    let width = 512, height = 300
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.16, alpha: 1), NSColor(calibratedRed: 0.32, green: 0.42, blue: 0.20, alpha: 1)])!.draw(in: bounds, angle: -24)
    NSColor(calibratedRed: 0.80, green: 0.94, blue: 0.51, alpha: 0.24).setFill()
    for x in stride(from: 22, to: width, by: 34) {
        for y in stride(from: 18, to: height, by: 34) where (x + y) % 3 == 0 {
            NSBezierPath(rect: NSRect(x: x, y: y, width: 5, height: 5)).fill()
        }
    }
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    (title as NSString).draw(in: NSRect(x: 30, y: 125, width: width - 60, height: 80), withAttributes: [
        .font: NSFont.systemFont(ofSize: 32, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ])
    ("FC / NES · 私人备份" as NSString).draw(in: NSRect(x: 30, y: 84, width: width - 60, height: 30), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.80, green: 0.94, blue: 0.51, alpha: 1),
        .paragraphStyle: paragraph,
    ])
    NSGraphicsContext.restoreGraphicsState()
    let filename = hash + ".png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename), options: .atomic)
    games[index]["cover"] = "covers/fallback/" + filename
    games[index]["coverEvidence"] = "未找到可验证的旧仓库编号封面；使用本地标题卡"
    made += 1
}

let output = try JSONSerialization.data(withJSONObject: games, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (output + Data("\n".utf8)).write(to: catalogURL, options: .atomic)
print("Generated fallback covers: \(made)")
