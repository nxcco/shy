// The app's icon, drawn rather than exported: the mark is a head rising from
// the bottom edge of the plate with two eyes looking out, someone shy just
// peeking in. It has no word on it, because a word turns into a smudge at
// 16 and 32 points (⌘Tab, Finder lists, the menu bar) and a shape does not.
// The word "shy" stays the logo in the app, as Design.swift's `Logomark`.
// It is a circle and two holes, given as numbers, so it stays a crisp vector
// at every size and needs nothing to build.
// The icon puts it on a plate — a Dock icon has to be an opaque square
// whether the logo itself wants a background or not.

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")

/// A dev build (build.sh) puts the mark on a yellow plate rather than a white
/// one, as Chrome Canary does, so the build from a worktree and the installed
/// app are told apart at a glance: in the Dock, in ⌘Tab, at 16 points.
let dev = ProcessInfo.processInfo.environment["SHY_DEV"] == "1"
let plateColor = dev ? NSColor(srgbRed: 1.0, green: 0.8, blue: 0.2, alpha: 1) : NSColor.white
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// The mark, in fractions of the plate's side, y down from its top edge. The
/// head's centre sits below the plate, so only its crown shows; the eyes are
/// holes in it, so they are always the plate's own colour, light or dark.
let head = (x: 0.5, y: 1.04, r: 0.40)
let eyes = [(x: 0.425, y: 0.77), (x: 0.575, y: 0.77)]
let eyeRadius = 0.034

/// The mark in `plate`, AppKit's y flipped from the fractions above. Not
/// clipped: draw() clips it to the plate's rounded shape.
func markPath(in plate: NSRect) -> NSBezierPath {
    func circle(_ x: Double, _ y: Double, _ r: Double) -> NSBezierPath {
        let side = plate.width
        return NSBezierPath(ovalIn: NSRect(
            x: plate.minX + (x - r) * side, y: plate.maxY - (y + r) * side,
            width: 2 * r * side, height: 2 * r * side))
    }
    let path = circle(head.x, head.y, head.r)
    for eye in eyes { path.append(circle(eye.x, eye.y, eyeRadius)) }
    path.windingRule = .evenOdd
    return path
}

func draw(_ size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Apple's grid: the shape takes 824 of 1024, and its corners are 22.37%.
    let s = size / 1024
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let radius = 824 * 0.2237 * s
    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    // A soft shadow under the plate, the way every icon on the Dock has one.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    plateColor.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The head, black, cut off by the plate's bottom edge.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
    markPath(in: plate).fill()
    NSGraphicsContext.restoreGraphicsState()
    return image
}

func write(_ image: NSImage, to url: URL, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { return }
    // The bitmap is asked for at the pixel size, whatever the screen thinks.
    let sized = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    sized.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sized)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = sized.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = draw(CGFloat(pixels))
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(image, to: out.appendingPathComponent(name), pixels: pixels)
    }
}
print("drew: \(out.path)")

// The same icon as an Icon Composer document, when a second path is given.
// macOS 26 lets the Dock show icons Dark, Clear or Tinted, and it can only
// do that well with an icon that says what each style should be: from the
// flat image above it made a darkened plate with the black mark still on
// it, black on black (#337). Here the plate and the mark are separate, so
// Dark turns them round — a white head on the ink colour, its eyes the ink
// showing through — and Tinted gets a white mark whose brightness the
// system tints. The light look is left as it is: the same white, the same
// ink, and no glass, gloss or shadow of its own.
// build.sh compiles it with actool; the images above stay the .icns.
if CommandLine.arguments.count > 2 {
    let doc = URL(fileURLWithPath: CommandLine.arguments[2])
    let assets = doc.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: doc)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

    // An Icon Composer canvas is the plate, 1024 points across, and it masks
    // its layers to the plate's shape, so the head is drawn whole and the
    // canvas cuts it off. Circles as two arcs each, filled even-odd.
    func circle(_ x: Double, _ y: Double, _ r: Double) -> String {
        let (cx, cy, rr) = (x * 1024, y * 1024, r * 1024)
        return "M\(cx - rr) \(cy)a\(rr) \(rr) 0 1 0 \(2 * rr) 0a\(rr) \(rr) 0 1 0 \(-2 * rr) 0Z"
    }
    let d = circle(head.x, head.y, head.r) + eyes.map { circle($0.x, $0.y, eyeRadius) }.joined()
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\
    <path fill-rule="evenodd" fill="#171717" d="\(d)"/></svg>
    """
    try svg.write(to: assets.appendingPathComponent("mark.svg"), atomically: true, encoding: .utf8)

    let white = #"{ "solid" : "srgb:1.00000,1.00000,1.00000,1.00000" }"#
    let yellow = #"{ "solid" : "srgb:1.00000,0.80000,0.20000,1.00000" }"#
    let ink = #"{ "solid" : "srgb:0.09000,0.09000,0.09000,1.00000" }"#
    // A dev build keeps its yellow in Dark too: the plate yellow in light,
    // the mark yellow on ink in dark.
    let plate = dev ? yellow : white
    let json = """
    {
      "fill" : \(plate),
      "fill-specializations" : [
        { "value" : \(plate) },
        { "appearance" : "dark", "value" : \(ink) }
      ],
      "groups" : [
        {
          "layers" : [
            {
              "name" : "mark",
              "image-name" : "mark.svg",
              "glass" : false,
              "fill-specializations" : [
                { "value" : \(ink) },
                { "appearance" : "dark", "value" : \(plate) },
                { "appearance" : "tinted", "value" : \(white) }
              ]
            }
          ],
          "shadow" : { "kind" : "none", "opacity" : 0.5 },
          "specular" : false,
          "translucency" : { "enabled" : false, "value" : 0.5 }
        }
      ],
      "supported-platforms" : { "squares" : [ "macOS" ] }
    }
    """
    try json.write(to: doc.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
    print("wrote: \(doc.path)")
}
