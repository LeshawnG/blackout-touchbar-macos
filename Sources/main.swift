// Blackout: a menu bar app that switches the MacBook Pro Touch Bar off.
//
// Built for Touch Bars with the known hardware fault where the whole bar flashes bright
// white. Drawing black can't hide that, because the fault happens after macOS has drawn
// the image, but powering the panel off can.
//
// Two layers, both undone when the app quits:
//  1. Panel power off (see Panel.swift): the same switch macOS uses when the Touch Bar
//     goes dark after you stop typing.
//  2. A full-width, all-black "system modal" Touch Bar as a backup, so anything that
//     briefly powers the panel back on shows black rather than buttons.
// macOS can power the panel back on (key presses, wake, unlock), so the app watches the
// panel state and switches it off again within milliseconds.
//
// Keyboard shortcuts, from any app (Carbon hotkeys, no Accessibility permission needed):
//   ⌥⌘0        Touch Bar On (normal)
//   ⌥⌘-        Touch Bar Off
//   ⌥⌘+ / ⌥⌘=  Touch Bar Peek: on while it's off, to use brightness / volume / mute; auto-off in 5 s
//              (or 3 s after the last change to one of them, whichever is later).
// The dark panel can't feel touches (see `touchtest`), so a shortcut has to wake it.
//
// Command line:  Blackout on | off | status    (panel power directly, e.g. if the app ever crashed)
//                Blackout key on | off | peek   (same as ⌥⌘0 / ⌥⌘- / ⌥⌘+ in the running app)
//                Blackout login on | off       (Start at Login)
//                Blackout touchtest            (guided test: does the bar feel touches when dark?)
//                Blackout version

import AppKit
import Carbon

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let repoURL = URL(string: "https://github.com/LeshawnG/blackout-touchbar-macos")!

/// Posted by `Blackout key …`; the running app treats it like the matching shortcut.
let shortcutNotification = Notification.Name("io.github.LeshawnG.Blackout.shortcut")

// MARK: - Command line mode

let cliArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn") }
if let command = cliArgs.first {
    switch command {
    case "on", "off":
        let ok = Panel.set(on: command == "on")
        print(ok ? "Touch Bar panel turned \(command)" : "Touch Bar did not accept '\(command)'")
        exit(ok ? 0 : 1)
    case "status":
        switch Panel.isLit {
        case .some(true):
            var line = "Touch Bar panel is lit"
            if let b = Panel.brightness {
                line += String(format: ", brightness %.0f%%", b.level * 100)
                if let nits = b.nits { line += String(format: " (%.0f nits)", nits) }
            }
            print(line)
        case .some(false): print("Touch Bar panel is dark")
        case .none: print("Touch Bar status unavailable")
        }
        exit(0)
    case "key":
        guard let action = cliArgs.dropFirst().first, ["on", "off", "peek"].contains(action) else {
            print("usage: Blackout key on|off|peek")
            exit(2)
        }
        DistributedNotificationCenter.default().postNotificationName(
            shortcutNotification, object: nil, userInfo: ["action": action], deliverImmediately: true)
        print("Sent '\(action)' to the running app")
        exit(0)
    case "login":
        guard let want = cliArgs.dropFirst().first, want == "on" || want == "off" else {
            print("usage: Blackout login on|off")
            exit(2)
        }
        do {
            try LoginItem.setEnabled(want == "on")
            print("Start at login: \(want)" + (want == "on" ? " (\(LoginItem.plistURL.path))" : ""))
            exit(0)
        } catch {
            print("Couldn't change start at login: \(error.localizedDescription)")
            exit(1)
        }
    case "touchtest":
        TouchTest.run()
    case "version":
        print("Blackout \(appVersion)")
        exit(0)
    default:
        print("usage: Blackout [on | off | status | key on|off|peek | login on|off | touchtest | version]")
        print("       (no argument starts the menu bar app)")
        exit(2)
    }
}

// MARK: - Black backup bar (private NSTouchBar system modal API)

private let canPresentBar = NSTouchBar.responds(
    to: NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"))

/// placement 1 = full width, over the Control Strip too.
private let fullWidthPlacement: Int64 = 1

private final class BlackView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 1000, height: 30) }
}

private func makeBlackBar() -> NSTouchBar {
    let item = NSCustomTouchBarItem(identifier: .init("io.github.LeshawnG.Blackout.black"))
    item.view = BlackView(frame: .zero)
    let bar = NSTouchBar()
    bar.templateItems = [item]
    bar.defaultItemIdentifiers = [item.identifier]
    return bar
}

// MARK: - Menu bar icon

/// A Touch Bar shaped icon: a long rounded bar with keys when on, empty and slashed when off.
func touchBarIcon(off: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
        NSColor.black.set()
        let bar = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4.5, width: 19, height: 7), xRadius: 2.5, yRadius: 2.5)
        bar.lineWidth = 1.5
        bar.stroke()
        if off {
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 3, y: 1.5))
            slash.line(to: NSPoint(x: 19, y: 14.5))
            slash.lineWidth = 1.8
            slash.lineCapStyle = .round
            slash.stroke()
        } else {
            for x in [4.5, 9.5, 14.5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 6.5, width: 3, height: 3), xRadius: 0.8, yRadius: 0.8).fill()
            }
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - App

final class Blackout: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let onItem = NSMenuItem(title: "Touch Bar On", action: #selector(turnOn), keyEquivalent: "0")
    private let offItem = NSMenuItem(title: "Touch Bar Off", action: #selector(turnOff), keyEquivalent: "-")
    private let peekItem = NSMenuItem(title: "Touch Bar Peek (auto-off in 5 s)", action: #selector(peek), keyEquivalent: "=")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let shortcutNote = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let trayID = NSTouchBarItem.Identifier("io.github.LeshawnG.Blackout.tray")
    private var bar: NSTouchBar?
    private var watchdog: Timer?
    private var isActive = false   // true = Touch Bar switched off

    private var hotKeys: [HotKey] = []
    private var unavailableShortcuts: [String] = []

    // Peek: the bar lit for a moment while switched off.
    private var isPeeking = false
    private var peekTimer: Timer?
    private var peekDeadline = Date()
    private let peekDuration: TimeInterval = 5          // ⌥⌘+ lights the bar this long
    private let peekAfterLastChange: TimeInterval = 3   // ...or until 3 s after the last brightness/volume/mute change

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One copy only (e.g. opened by hand while the login copy is already running).
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me }) {
            exit(0)
        }

        if Mover.offerIfNeeded() { return }   // relaunching from Applications
        LoginItem.repair()

        registerShortcuts()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(shortcutFromCommandLine(_:)), name: shortcutNotification, object: nil)

        buildMenu()

        // macOS powers the panel back on after key presses, wake and unlock; switch it off again.
        Panel.onStatusChange { _ in
            DispatchQueue.main.async { [weak self] in self?.enforce() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(woke), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(woke), name: .init("com.apple.screenIsUnlocked"), object: nil)

        // Start with the Touch Bar on (and relight it if a crash ever left it dark).
        if Panel.isLit == false { Panel.set(on: true) }
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        setActive(false)
    }

    // MARK: Menu bar icon and menu
    //
    // Click the icon: switch the Touch Bar on/off.
    // Right-click (or Control/Option-click): the menu.

    private var canSwitch: Bool { Panel.isAvailable || canPresentBar }

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self
        if canSwitch {
            for item in [onItem, offItem, peekItem] {
                item.target = self
                item.keyEquivalentModifierMask = [.command, .option]
                menu.addItem(item)
            }
            statusLine.isEnabled = false
            menu.addItem(statusLine)
            if !unavailableShortcuts.isEmpty {
                shortcutNote.title = "Taken by another app: \(unavailableShortcuts.joined(separator: ", "))"
                shortcutNote.isEnabled = false
                menu.addItem(shortcutNote)
            }
        } else {
            let note = NSMenuItem(title: "This Mac or macOS can't switch the Touch Bar off", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Blackout", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Blackout (Touch Bar back on)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshUI()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshUI() }   // fresh brightness reading

    @objc private func iconClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true
        if wantsMenu || !canSwitch {
            // Attach the menu just long enough to open it, so a plain click stays a switch.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            setActive(!isActive)
        }
    }

    private func refreshUI() {
        onItem.state = isActive ? .off : .on
        offItem.state = isActive ? .on : .off
        peekItem.isEnabled = isActive
        statusLine.title = statusText()

        loginItem.state = LoginItem.isEnabled ? .on : .off
        loginItem.isEnabled = LoginItem.canEnable || LoginItem.isEnabled
        loginItem.title = LoginItem.canEnable ? "Start at Login" : "Start at Login (move to Applications first)"

        guard let button = statusItem.button else { return }
        let image = touchBarIcon(off: isActive && !isPeeking)
        image.accessibilityDescription = isActive ? "Touch Bar off" : "Touch Bar on"
        button.image = image
        button.toolTip = "Blackout: Touch Bar " + (isActive ? "off" : "on")
            + ". Click to switch, right-click for the menu. ⌥⌘0 Touch Bar On · ⌥⌘- Touch Bar Off · ⌥⌘+ Touch Bar Peek"
    }

    private func statusText() -> String {
        if isActive && !isPeeking {
            return Panel.isAvailable ? "Touch Bar is off (panel powered down)" : "Touch Bar is black (power control unavailable)"
        }
        var text = isPeeking ? "Touch Bar Peek · auto-off in 5 s" : "Touch Bar is on"
        if let b = Panel.brightness, Panel.isLit == true {
            text += String(format: " · brightness %.0f%%", b.level * 100)
            if let nits = b.nits { text += String(format: " (%.0f nits)", nits) }
        }
        return text
    }

    // MARK: On / off

    private func setActive(_ on: Bool) {
        stopPeek()
        isActive = on
        if on {
            presentBlackBar()
            Panel.set(on: false)
            startWatchdog()
        } else {
            watchdog?.invalidate()
            watchdog = nil
            dismissBlackBar()
            Panel.set(on: true)
        }
        refreshUI()
    }

    private func presentBlackBar() {
        guard canPresentBar else { return }
        dismissBlackBar()
        Panel.hideCloseBox()  // no little "x" button on the left
        let fresh = makeBlackBar()
        NSTouchBar.presentSystemModalTouchBar(fresh, placement: fullWidthPlacement, systemTrayItemIdentifier: trayID)
        bar = fresh
    }

    private func dismissBlackBar() {
        if let old = bar {
            NSTouchBar.dismissSystemModalTouchBar(old)
            bar = nil
        }
    }

    /// Switch the panel off again if macOS lit it.
    private func enforce() {
        guard isActive, !isPeeking, Panel.isLit == true else { return }
        Panel.set(on: false)
    }

    /// Backup for a missed status callback. Reading the status is cheap.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.enforce() }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    @objc private func turnOn() { setActive(false) }
    @objc private func turnOff() { setActive(true) }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Start at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refreshUI()
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Switches the Touch Bar off: a fix for flashing and flickering Touch Bars.\n\n"
                + "⌥⌘0  Touch Bar On\n⌥⌘-  Touch Bar Off\n⌥⌘+  Touch Bar Peek (auto-off in 5 s)\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(string: repoURL.absoluteString.replacingOccurrences(of: "https://", with: ""),
                                          attributes: [.font: NSFont.systemFont(ofSize: 11), .link: repoURL]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: Shortcuts and peek

    private func registerShortcuts() {
        let optCmd = UInt32(cmdKey | optionKey)
        let shortcuts: [(name: String, key: Int, mods: UInt32, action: () -> Void)] = [
            ("⌥⌘0", kVK_ANSI_0, optCmd, { [weak self] in self?.turnOn() }),
            ("⌥⌘-", kVK_ANSI_Minus, optCmd, { [weak self] in self?.turnOff() }),
            ("⌥⌘=", kVK_ANSI_Equal, optCmd, { [weak self] in self?.peek() }),
            ("⌥⌘+", kVK_ANSI_Equal, optCmd | UInt32(shiftKey), { [weak self] in self?.peek() }),
        ]
        for (index, shortcut) in shortcuts.enumerated() {
            if let hotKey = HotKey(keyCode: UInt32(shortcut.key), modifiers: shortcut.mods,
                                   id: UInt32(index + 1), handler: shortcut.action) {
                hotKeys.append(hotKey)
            } else {
                unavailableShortcuts.append(shortcut.name)
            }
        }
        NSLog("Blackout: shortcuts registered %d of %d%@", hotKeys.count, shortcuts.count,
              unavailableShortcuts.isEmpty ? "" : " (taken: \(unavailableShortcuts.joined(separator: " ")))")
    }

    /// `Blackout key on|off|peek`
    @objc private func shortcutFromCommandLine(_ note: Notification) {
        switch note.userInfo?["action"] as? String {
        case "on": turnOn()
        case "off": turnOff()
        case "peek": peek()
        default: break
        }
    }

    /// ⌥⌘+: light the bar for 5 s while it's off. Does nothing when the bar is already on.
    @objc private func peek() {
        guard isActive else { return }
        if isPeeking {
            peekDeadline = max(peekDeadline, Date().addingTimeInterval(peekDuration))  // pressed again: restart the 5 s
        } else {
            startPeek()
        }
    }

    private func startPeek() {
        isPeeking = true
        dismissBlackBar()
        Panel.set(on: true)
        peekDeadline = Date().addingTimeInterval(peekDuration)
        lastControls = Controls.now()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkPeek() }
        RunLoop.main.add(timer, forMode: .common)
        peekTimer = timer
        refreshUI()
    }

    /// What the bar is used for: brightness, volume and mute. The bar stays lit while any of them
    /// is changing. (Generic "user input" also fires for typing and a palm on the trackpad.)
    private struct Controls: Equatable {
        let muted: Bool?
        let volume: Int?       // in 0.1% steps, so tiny float noise doesn't count
        let brightness: Int?
        static func now() -> Controls {
            Controls(muted: outputMuted(),
                     volume: outputVolume().map { Int(($0 * 1000).rounded()) },
                     brightness: screenBrightness().map { Int(($0 * 1000).rounded()) })
        }
    }
    private var lastControls: Controls?

    private func checkPeek() {
        let current = Controls.now()
        if let last = lastControls, current != last {
            peekDeadline = max(peekDeadline, Date().addingTimeInterval(peekAfterLastChange))
        }
        lastControls = current
        if Date() >= peekDeadline { endPeek() }
    }

    private func endPeek() {
        guard isPeeking else { return }
        stopPeek()
        if isActive {
            presentBlackBar()
            Panel.set(on: false)
        }
        refreshUI()
    }

    private func stopPeek() {
        peekTimer?.invalidate()
        peekTimer = nil
        isPeeking = false
    }

    @objc private func woke() {
        if isPeeking { endPeek() }
        guard isActive else { return }
        // The Touch Bar service takes a moment to come back after wake/unlock.
        for delay in [0.25, 0.75, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isActive else { return }
                if delay == 1.5 { self.presentBlackBar() }
                self.enforce()
            }
        }
    }
}

// Quit cleanly on Ctrl-C / `kill` so the Touch Bar is always turned back on.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { NSApp.terminate(nil) }
    source.resume()
    signalSources.append(source)
}

let app = NSApplication.shared
let delegate = Blackout()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
