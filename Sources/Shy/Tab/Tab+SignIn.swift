import Combine
import ImageIO
import SwiftUI
import WebKit

// A passkey box on the page, and picking things on it (Forms.swift is the page's side).
extension Tab {
    /// From the page, in CSS pixels; passed on in points. Page zoom is the
    /// only scale between the two that matters here.
    func fieldFocused(_ rect: CGRect?) {
        guard let rect else {
            onField?(self, nil)
            return
        }
        let zoom = built?.pageZoom ?? 1
        onField?(self, CGRect(
            x: rect.minX * zoom, y: rect.minY * zoom,
            width: rect.width * zoom, height: rect.height * zoom
        ))
    }

    func picked(selector: String, label: String, note: String) {
        onPick?(self, selector, label, note)
    }

    /// Show one hidden thing while the pointer rests on its row in the list.
    func peek(_ selector: String, keeping css: String) {
        web.evaluateInShy(
            "window.__officeVeil && window.__officeVeil.peek(`\(escape(css))`, `\(escape(selector))`)"
        )
    }

    func unpeek(_ css: String) {
        web.evaluateInShy("window.__officeVeil && window.__officeVeil.unpeek(`\(escape(css))`)")
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    func pickingEnded() { onPickEnd?(self) }

    func pickingFailed(_ reason: String) { onPickTrouble?(self, reason) }
}
