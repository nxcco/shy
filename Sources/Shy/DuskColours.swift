import Foundation

// Dark pages, in the site's own colours (see Dusk.swift for when and why).
//
// For every rule of the page's that sets a colour, a twin: the same
// selector, in the same order, with the colour taken to dark. The twins go
// in after the page's own sheets, so the cascade settles every element
// exactly as it did for the site, only in dark colours. Nothing is turned
// over, so a picture is never touched and a colour keeps its gamut.
//
// The browser does the arithmetic. A twin is written in relative colour
// syntax, `oklch(from <the site's colour> <new lightness> c h / alpha)`,
// which takes any colour the site names: hex, oklch, a P3 colour, a
// system colour, or a variable whose value is only known on the element.
// Lightness is moved along one of three curves, by the part a colour
// plays; hue and chroma are kept.
//
// WebKit has had relative colour syntax since Safari 18 (macOS 15); before
// that, the filter (Dusk.swift) does the darkening on its own.

enum DuskColours {
    /// Where the engine goes in the page script (Dusk.script).
    static let slot = "/*COLOURS*/"

    /// A function of the page script's, called once per page with the
    /// document and the page script's own sheets, which aren't the page's.
    /// Nil where the browser can't do relative colours.
    static let engine = Scripts.load("dusk-colours")
}
