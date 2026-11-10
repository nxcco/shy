import Foundation

/// A website may return only to an extension page its manifest exposes.
/// Unsupported declarations are refused, never made more permissive.
enum ExtensionRedirectPolicy {
    /// A declarativeNetRequest redirect to an extension's own file arrives
    /// with its `?` and `#` escaped into the path: WebKit sets the rule's
    /// extensionPath as a path, where Chrome reads "/blocked.html#site" as a
    /// file and a fragment. The first escaped one is put back as Chrome
    /// reads it, so the page gets its query and fragment and the file is
    /// the one the extension ships. Anything else is left as it is.
    static func ruleTarget(_ target: URL) -> URL {
        guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false),
              components.percentEncodedQuery == nil, components.percentEncodedFragment == nil
        else { return target }
        let path = components.percentEncodedPath
        let lower = path.lowercased()
        let query = lower.range(of: "%3f"), fragment = lower.range(of: "%23")
        guard let first = [query, fragment].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { return target }
        let at = path.index(path.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: first.lowerBound))
        let rest = String(path[path.index(at, offsetBy: 3)...])
        components.percentEncodedPath = String(path[..<at])
        if first == query {
            if let hash = rest.lowercased().range(of: "%23") {
                let split = rest.index(rest.startIndex, offsetBy: rest.lowercased().distance(from: rest.lowercased().startIndex, to: hash.lowerBound))
                components.percentEncodedQuery = String(rest[..<split])
                components.percentEncodedFragment = String(rest[rest.index(split, offsetBy: 3)...])
            } else {
                components.percentEncodedQuery = rest
            }
        } else {
            components.percentEncodedFragment = rest
        }
        return components.url ?? target
    }

    /// `fromRule`: an extension's own declarativeNetRequest rule sent the
    /// tab there, not the site, and Chrome's rule then applies to plain
    /// http sites too: the file has to be exposed to the site, by scheme.
    static func allows(target: URL, sourceOrigin: URL, manifest: [String: Any], fromRule: Bool = false) -> Bool {
        let sourceScheme = sourceOrigin.scheme?.lowercased() ?? ""
        guard target.scheme?.lowercased() == "chrome-extension",
              target.host != nil, target.user == nil, target.password == nil, target.port == nil,
              sourceScheme == "https" || (fromRule && sourceScheme == "http"),
              sourceOrigin.host != nil, sourceOrigin.user == nil, sourceOrigin.password == nil,
              let components = URLComponents(url: target, resolvingAgainstBaseURL: false)
        else { return false }

        // Fail closed on encodings with inconsistent path interpretations.
        let encoded = components.percentEncodedPath
        let lower = encoded.lowercased()
        guard encoded.hasPrefix("/"),
              !lower.contains("%2f"), !lower.contains("%5c"),
              let decoded = encoded.removingPercentEncoding,
              !decoded.contains("\\"), !decoded.contains("%"),
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return false }
        let path = String(decoded.dropFirst())
        guard !path.isEmpty,
              !path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0 == "." || $0 == ".." || $0.isEmpty })
        else { return false }

        // MV2 lists resources, without MV3's per-origin declarations.
        if (manifest["manifest_version"] as? Int) == 2,
           let resources = manifest["web_accessible_resources"] as? [String] {
            return resources.contains { resource(path, matches: $0) }
        }

        guard (manifest["manifest_version"] as? Int) == 3,
              let rules = manifest["web_accessible_resources"] as? [[String: Any]]
        else { return false }
        return rules.contains { rule in
            // Dynamic extension origins need separate handling; refuse them here.
            if let dynamic = rule["use_dynamic_url"] {
                guard let enabled = dynamic as? Bool, !enabled else { return false }
            }
            guard let resources = rule["resources"] as? [String],
                  let origins = rule["matches"] as? [String],
                  resources.contains(where: { resource(path, matches: $0) })
            else { return false }
            return origins.contains { origin(sourceOrigin, matches: $0) }
        }
    }

    private static func resource(_ path: String, matches pattern: String) -> Bool {
        // Only the '*' wildcard. Other regex metacharacters stay literal.
        guard !pattern.isEmpty, !pattern.contains("\\"), !pattern.contains("%"),
              !pattern.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return false }
        let clean = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern
        guard !clean.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else { return false }
        return glob(Array(clean.utf16), matches: Array(path.utf16))
    }

    /// The whole of `text` against `pattern`, where `*` stands for any run
    /// of characters, `/` included. Walked once with a single place to go
    /// back to, the last `*`: the path is the page's to make as long as it
    /// likes, and a regex of several `.*` took seconds over a long one, on
    /// the main thread.
    static func glob(_ pattern: [UInt16], matches text: [UInt16]) -> Bool {
        let star = UInt16(UInt8(ascii: "*"))
        var p = 0, t = 0
        var lastStar: Int?, resume = 0
        while t < text.count {
            if p < pattern.count, pattern[p] == star {
                lastStar = p
                resume = t
                p += 1
            } else if p < pattern.count, pattern[p] == text[t] {
                p += 1
                t += 1
            } else if let lastStar {
                // The last `*` takes one more character, and the rest is tried again from there.
                p = lastStar + 1
                resume += 1
                t = resume
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == star { p += 1 }
        return p == pattern.count
    }

    private static func origin(_ source: URL, matches pattern: String) -> Bool {
        // HTTPS callers, and http ones only for a rule's redirect (see
        // allows()). MV3 origin patterns have a /* path. Unsupported
        // syntax is deliberately rejected.
        if pattern == "<all_urls>" { return true }
        guard let separator = pattern.range(of: "://"), let host = source.host?.lowercased() else { return false }
        let scheme = String(pattern[..<separator.lowerBound]).lowercased()
        guard scheme == source.scheme?.lowercased() || scheme == "*" else { return false }
        let remainder = String(pattern[separator.upperBound...])
        guard let slash = remainder.firstIndex(of: "/"), remainder[slash...] == "/*" else { return false }
        let allowed = String(remainder[..<slash]).lowercased()
        guard !allowed.isEmpty, !allowed.contains(":"), !allowed.contains("@"),
              !allowed.contains("%"), !allowed.contains("\\") else { return false }
        if allowed == "*" { return true }
        if allowed.hasPrefix("*.") {
            let suffix = String(allowed.dropFirst(2))
            guard !suffix.isEmpty, !suffix.contains("*") else { return false }
            return host == suffix || host.hasSuffix("." + suffix)
        }
        return !allowed.contains("*") && host == allowed
    }
}
