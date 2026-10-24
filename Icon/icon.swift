// The app's icon, drawn rather than exported: the mark is the word "shy" in
// black newspaper type, read from its own path data rather than set as text
// or loaded as an image, so it stays a crisp vector at every size instead of
// a raster scaled up, and needs no font to build.
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

/// "shy", lowercase, in Times New Roman Bold — the face The Times had cut
/// for its own pages, so it reads as print — taken from the font's glyph
/// outlines (CTFontCreatePathForGlyph at 1000 to the em, its quadratic
/// curves raised to cubic ones) on the word's own bounding box. The same
/// path is in Design.swift's `Logomark` — one shape, two places.
let canvas = (width: 1396.5, height: 877.9)
let markData = "M282.7 192.9L290 348.6L273.4 348.6C253.6 302.4 233 270.8 211.7 253.9C190.3 237 169.1 228.5 147.9 228.5C134.6 228.5 123.2 233 113.8 241.9C104.3 250.9 99.6 261.2 99.6 272.9C99.6 281.7 102.9 290.2 109.4 298.3C119.8 311.7 148.9 334.6 196.8 366.9C244.6 399.3 276.1 426.8 291.3 449.5C306.4 472.1 314 497.4 314 525.4C314 550.8 307.6 575.7 294.9 600.1C282.2 624.5 264.3 643.2 241.2 656.2C218.1 669.3 192.5 675.8 164.6 675.8C142.7 675.8 113.6 668.9 77.1 655.3C67.4 651.7 60.7 649.9 57.1 649.9C46.4 649.9 37.4 658 30.3 674.3L14.2 674.3L6.3 510.3L22.9 510.3C37.6 553.2 57.7 585.4 83.3 606.9C108.8 628.4 133 639.2 155.8 639.2C171.4 639.2 184.2 634.4 194.1 624.8C204 615.2 209 603.5 209 589.8C209 574.2 204.1 560.7 194.3 549.3C184.6 537.9 162.8 520.7 128.9 497.6C79.1 463.1 46.9 436.7 32.2 418.5C10.7 391.8 0 362.3 0 330.1C0 294.9 12.1 263.1 36.4 234.6C60.6 206.1 95.7 191.9 141.6 191.9C166.3 191.9 190.3 197.9 213.4 210C222.2 214.8 229.3 217.3 234.9 217.3C240.7 217.3 245.4 216.1 249 213.6C252.6 211.2 258.3 204.3 266.1 192.9ZM569.8 0L569.8 264.2C594.9 237.8 617.8 219.2 638.7 208.3C659.5 197.3 681.2 191.9 703.6 191.9C732.3 191.9 756.8 200 777.1 216.3C797.4 232.6 811 251.7 817.6 273.7C824.3 295.7 827.6 332.7 827.6 384.8L827.6 563C827.6 597.8 830.9 619.5 837.4 628.2C843.9 636.8 857.1 642.3 877 644.5L877 662.1L645.5 662.1L645.5 644.5C661.8 642.3 674 635.7 682.1 625C688 616.5 690.9 595.9 690.9 563L690.9 359.4C690.9 321.6 689.5 297.9 686.5 288.3C683.6 278.7 678.6 271.2 671.6 265.9C664.6 260.5 656.7 257.8 647.9 257.8C634.9 257.8 622.2 262.3 609.9 271.2C597.5 280.2 584.1 295.9 569.8 318.4L569.8 563C569.8 595.5 572.3 615.9 577.1 624C583.3 635.1 596 641.9 615.2 644.5L615.2 662.1L383.8 662.1L383.8 644.5C403 642.6 416.7 636.4 424.8 626C430.3 618.8 433.1 597.8 433.1 563L433.1 99.1C433.1 64.6 429.9 43.1 423.6 34.7C417.2 26.2 404 20.7 383.8 18.1L383.8 0ZM1148.9 680.7L1001.5 342.3C979.3 291.2 963 259.8 952.4 248C941.8 236.3 929 228.2 914.1 223.6L914.1 205.6L1156.7 205.6L1156.7 223.6C1140.8 224.3 1129.6 227.4 1123 232.9C1116.5 238.4 1113.3 245.1 1113.3 252.9C1113.3 265.3 1121.4 289.7 1137.7 326.2L1215.8 504.9L1269 366.7C1288.2 317.5 1297.9 283.4 1297.9 264.2C1297.9 252.1 1293.9 242.5 1285.9 235.4C1277.9 228.2 1263.8 224.3 1243.7 223.6L1243.7 205.6L1396.5 205.6L1396.5 223.6C1381.5 225.3 1369.3 231 1359.9 241C1350.4 250.9 1334.6 284.7 1312.5 342.3L1182.1 680.7C1149.3 765.3 1124.8 817.4 1108.9 836.9C1086.4 864.3 1058.3 877.9 1024.4 877.9C997.4 877.9 975.5 870.2 958.7 854.7C942 839.3 933.6 820.6 933.6 798.8C933.6 779.9 939.4 764.3 950.9 752C962.5 739.6 976.7 733.4 993.7 733.4C1009.9 733.4 1023 738.6 1033 749C1042.9 759.4 1048 775.6 1048.3 797.4C1048.7 809.7 1050.1 817.7 1052.7 821.3C1055.3 824.9 1059.1 826.7 1064 826.7C1071.8 826.7 1080.1 821.9 1088.9 812.5C1101.9 798.8 1117.2 767.6 1134.8 718.8Z"

/// How much of the plate's width the word spans: wide enough to read from
/// across the Dock, with a column's margin left either side.
let share: CGFloat = 0.74

/// A tiny reader for the one path the mark is: absolute M, L, H, V, C, Z —
/// all a font's outlines need once their quadratics are cubic.
func svgCommands(_ d: String) -> [(Character, [CGFloat])] {
    var out: [(Character, [CGFloat])] = []
    var current: Character?
    var numbers: [CGFloat] = []
    var token = ""
    func flushNumber() {
        if !token.isEmpty, let v = Double(token) { numbers.append(CGFloat(v)) }
        token = ""
    }
    for ch in d {
        if "MLHVCZmlhvcz".contains(ch) {
            flushNumber()
            if let current { out.append((current, numbers)) }
            current = ch
            numbers = []
        } else if ch == " " || ch == "," {
            flushNumber()
        } else if ch == "-" && !token.isEmpty && !token.hasSuffix("e") {
            flushNumber()
            token = "-"
        } else {
            token.append(ch)
        }
    }
    flushNumber()
    if let current { out.append((current, numbers)) }
    return out
}

/// The mark, fit to `fraction` of `plate`'s width and centred on it. SVG's y
/// grows downward and AppKit's upward, so every y is flipped on the way in;
/// the path is filled even-odd, as Logomark is, though no letter of "shy"
/// has a counter to keep open.
func markPath(in plate: NSRect, fraction: CGFloat) -> NSBezierPath {
    let scale = plate.width * fraction / canvas.width
    let ox = plate.midX - canvas.width * scale / 2
    let oy = plate.midY - canvas.height * scale / 2
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: ox + x * scale, y: oy + (canvas.height - y) * scale)
    }
    let path = NSBezierPath()
    path.windingRule = .evenOdd
    var last = NSPoint.zero
    var start = NSPoint.zero
    for (c, n) in svgCommands(markData) {
        switch c {
        case "M": last = NSPoint(x: n[0], y: n[1]); start = last; path.move(to: pt(n[0], n[1]))
        case "L": last = NSPoint(x: n[0], y: n[1]); path.line(to: pt(n[0], n[1]))
        case "H": last.x = n[0]; path.line(to: pt(last.x, last.y))
        case "V": last.y = n[0]; path.line(to: pt(last.x, last.y))
        case "C":
            var k = 0
            while k + 5 < n.count {
                path.curve(to: pt(n[k + 4], n[k + 5]), controlPoint1: pt(n[k], n[k + 1]), controlPoint2: pt(n[k + 2], n[k + 3]))
                last = NSPoint(x: n[k + 4], y: n[k + 5])
                k += 6
            }
        case "Z": path.close(); last = start
        default: break
        }
    }
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

    // The word, black on the plate, centred on its own box — the y's tail
    // below balances the h's stem above.
    NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
    markPath(in: plate, fraction: share).fill()
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
// Dark turns them round — the word in white on the ink colour, like a
// reversed-out headline — and Tinted gets a white mark whose brightness the
// system tints. The light look is left as it is: the same white, the same
// ink, the mark at the same size, and no glass, gloss or shadow of its own.
// build.sh compiles it with actool; the images above stay the .icns.
if CommandLine.arguments.count > 2 {
    let doc = URL(fileURLWithPath: CommandLine.arguments[2])
    let assets = doc.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: doc)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

    // An Icon Composer canvas is the plate, 1024 points across; the mark
    // takes the same share of it as it does of the plate drawn above.
    let width = 1024 * share
    let height = width * canvas.height / canvas.width
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(canvas.width) \(canvas.height)">\
    <path fill-rule="evenodd" fill="#171717" d="\(markData)"/></svg>
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
