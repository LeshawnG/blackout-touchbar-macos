// Start at Login, as a per-user LaunchAgent in ~/Library/LaunchAgents.
// Untick it in the menu, or delete the plist, to undo it.

import Foundation

enum LoginItem {
    static var label: String { Bundle.main.bundleIdentifier ?? "io.github.LeshawnG.Blackout" }

    /// Labels used by development builds before the app had its public bundle ID.
    private static let legacyLabels = ["local.touchbar.blackout"]

    static func plistURL(for label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var plistURL: URL { plistURL(for: label) }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// A quarantined app opened from Downloads runs from a temporary, read-only copy
    /// ("App Translocation"); pointing a login item there would break after a restart.
    static var canEnable: Bool { !Bundle.main.bundlePath.contains("/AppTranslocation/") }

    static func setEnabled(_ on: Bool) throws {
        guard on else {
            if isEnabled { try FileManager.default.removeItem(at: plistURL) }
            return
        }
        guard canEnable else {
            throw NSError(domain: label, code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Move Blackout to your Applications folder first, then turn on Start at Login."])
        }
        guard let executable = Bundle.main.executablePath else {
            throw NSError(domain: label, code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't find the app's executable."])
        }
        let agent: NSDictionary = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "AbandonProcessGroup": true,   // lets "Move to Applications" relaunch the app
        ]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try agent.write(to: plistURL)
    }

    /// Run at launch: carry over a login item from an older build, and re-point the login item
    /// at this copy if the app it pointed to has been moved or deleted.
    static func repair() {
        let fm = FileManager.default
        var wanted = isEnabled
        for old in legacyLabels where fm.fileExists(atPath: plistURL(for: old).path) {
            try? fm.removeItem(at: plistURL(for: old))
            wanted = true
        }
        guard wanted, canEnable else { return }
        let target = (NSDictionary(contentsOf: plistURL)?["ProgramArguments"] as? [String])?.first
        if target == nil || !fm.fileExists(atPath: target!) {
            try? setEnabled(true)
        }
    }
}
