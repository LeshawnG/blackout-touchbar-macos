// "Move to Applications?" on first launch, the way many downloaded Mac apps do it.
// The app works from anywhere; living in Applications keeps Start at Login pointing
// at a copy that won't move.

import AppKit

enum Mover {
    private static let skipKey = "SkipMoveToApplications"

    static var isInApplications: Bool {
        let path = originalBundleURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    /// A source checkout's own build (build/Blackout.app next to build.sh): never offer to move it.
    private static var isDevelopmentBuild: Bool {
        let parent = originalBundleURL.deletingLastPathComponent()
        return parent.lastPathComponent == "build"
            && FileManager.default.fileExists(atPath: parent.deletingLastPathComponent().appendingPathComponent("build.sh").path)
    }

    /// Where the app really is. A quarantined download runs from a temporary read-only copy
    /// ("App Translocation"); Security.framework can tell us the original location.
    static var originalBundleURL: URL {
        let url = Bundle.main.bundleURL
        guard url.path.contains("/AppTranslocation/"),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let sym = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return url }
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        return unsafeBitCast(sym, to: Original.self)(url as CFURL, nil)?.takeRetainedValue() as URL? ?? url
    }

    /// Shows the prompt if it's worth asking. Returns true if the app is relaunching from Applications.
    static func offerIfNeeded() -> Bool {
        guard !isInApplications, !isDevelopmentBuild, !UserDefaults.standard.bool(forKey: skipKey) else { return false }

        let alert = NSAlert()
        alert.messageText = "Move Blackout to your Applications folder?"
        alert.informativeText = "Blackout works from anywhere, but keeping it in Applications means Start at Login can always find it."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: skipKey) }
        guard response == .alertFirstButtonReturn else { return false }

        do {
            let installed = try install(originalBundleURL, into: URL(fileURLWithPath: "/Applications"))
            relaunch(installed)
            return true
        } catch {
            let failed = NSAlert()
            failed.messageText = "Couldn't move Blackout"
            failed.informativeText = "\(error.localizedDescription)\n\nYou can drag Blackout into Applications yourself."
            failed.runModal()
            return false
        }
    }

    /// Copies the app into `folder`, replacing an older copy (which goes to the Trash),
    /// then moves the original to the Trash. Returns the new location.
    @discardableResult
    static func install(_ source: URL, into folder: URL) throws -> URL {
        let fm = FileManager.default
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        guard destination.standardizedFileURL != source.standardizedFileURL else { return destination }
        if fm.fileExists(atPath: destination.path) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: source, to: destination)
        // You already approved this app when you opened it. Clearing the download flag on the
        // installed copy stops macOS running it from a temporary read-only location.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? xattr.run()
        xattr.waitUntilExit()
        try? fm.trashItem(at: source, resultingItemURL: nil)
        return destination
    }

    /// Opens the app at `url` once this process has quit (only one copy runs at a time).
    static func relaunch(_ url: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\"", url.path]
        try? shell.run()
        NSApp.terminate(nil)
    }
}
