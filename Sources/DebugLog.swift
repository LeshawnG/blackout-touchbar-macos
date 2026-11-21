// Blackout's event log, for chasing the "Touch Bar stays dark after Touch Bar On" bug.
//
//   ~/Library/Logs/Blackout/Blackout.log   (plain text, kept under 1 MB, one old copy as .log.1)
//   log show --last 1d --predicate 'subsystem == "io.github.LeshawnG.Blackout"'
//
// It records switches, wakes, status changes while the bar should be on, and a panel reading
// (status, dimming step, brightness, nits) around each one. Nothing else is written.

import Foundation
import os

enum DebugLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Blackout/Blackout.log")

    private static let osLog = OSLog(subsystem: "io.github.LeshawnG.Blackout", category: "panel")
    private static let maxBytes = 1_000_000

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ text: String) {
        os_log("%{public}@", log: osLog, type: .default, text)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        let line = Data("\(stamp.string(from: Date())) \(text)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            handle.closeFile()
        } else {
            try? line.write(to: url)
        }
    }
}
