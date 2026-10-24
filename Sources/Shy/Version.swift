import Foundation
import Security

/// This build's version and build number, as Info.plist has them.
enum Version {
    nonisolated static var number: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    nonisolated static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }
}

/// What a Developer ID signature from Office Commun's team looks like: the
/// AI add-on's engine is checked against it before it is run (AIEngine).
enum Signer {
    nonisolated static let team = "7BYKA895MC"

    /// Anchored at Apple, issued through the Developer ID intermediate, a
    /// Developer ID Application leaf, the team's own; and the identifier,
    /// when one is given.
    nonisolated static func developerID(team: String, identifier: String?) -> SecRequirement? {
        let text = "anchor apple generic" + (identifier.map { " and identifier \"\($0)\"" } ?? "")
            + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"
            + " and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }
}
