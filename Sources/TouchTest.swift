// `Blackout touchtest`: a guided ~2-minute experiment that answers
// "does the Touch Bar still feel touches while its panel is powered off?"
//
// Timeline (an on-screen window with a countdown, plus a spoken prompt, announces each step):
//   0:00  get ready: bar normal, hands off keyboard and trackpad
//   0:20  phase 1, bar dark + black cover:   tap anywhere on the bar 5 times, slowly
//   0:50  phase 2, bar dark, buttons live:   tap where Mute is, 2 times, ~2 s apart
//   1:20  phase 3, bar lit and normal:       nudge trackpad, tap Mute 2 times, slide Volume
//   1:50  done: panel back on, mute restored to how it started
//
// It only logs signals: panel wake/status, touches on the black cover, input-idle resets,
// and mute/volume/screen-brightness changes. Nothing is written to disk.

import AppKit
import CoreAudio
import AudioToolbox

// MARK: - Signals we can read

private func defaultOutputDevice() -> AudioObjectID? {
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMaster)
    return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr ? id : nil
}

func outputMuted() -> Bool? {
    guard let dev = defaultOutputDevice() else { return nil }
    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                          mScope: kAudioDevicePropertyScopeOutput,
                                          mElement: kAudioObjectPropertyElementMaster)
    return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr ? value != 0 : nil
}

private func setOutputMuted(_ muted: Bool) {
    guard let dev = defaultOutputDevice() else { return }
    var value = UInt32(muted ? 1 : 0)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                          mScope: kAudioDevicePropertyScopeOutput,
                                          mElement: kAudioObjectPropertyElementMaster)
    AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
}

func outputVolume() -> Float? {
    guard let dev = defaultOutputDevice() else { return nil }
    var value = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
                                          mScope: kAudioDevicePropertyScopeOutput,
                                          mElement: kAudioObjectPropertyElementMaster)
    return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr ? value : nil
}

let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

func screenBrightness() -> Float? {
    guard let ds = displayServices, let sym = dlsym(ds, "DisplayServicesGetBrightness") else { return nil }
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    var value: Float = 0
    return unsafeBitCast(sym, to: Get.self)(CGMainDisplayID(), &value) == 0 ? value : nil
}

/// Seconds since any keyboard / mouse / trackpad (and maybe Touch Bar) input.
private func inputIdleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - Black cover that reports touches

private final class TouchLogView: NSView {
    var report: ((String) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        allowedTouchTypes = [.direct]
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 1000, height: 30) }
    override func touchesBegan(with event: NSEvent) { report?("cover: touch began") }
    override func touchesEnded(with event: NSEvent) { report?("cover: touch ended") }
    override func mouseDown(with event: NSEvent) { report?("cover: mouseDown") }
}

// MARK: - The test

final class TouchTest: NSObject, NSApplicationDelegate {
    static func run() -> Never {
        let app = NSApplication.shared
        let test = TouchTest()
        app.delegate = test
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }

    private let start = Date()
    private var phase = "ready"
    private var dark = false
    private var bar: NSTouchBar?
    private var poller: Timer?
    private var counts: [String: Int] = [:]
    private var order: [String] = []
    private var signalSources: [DispatchSourceSignal] = []

    private var lastIdle = Double.infinity
    private var lastIdleLog = Date.distantPast
    private var lastLit: Bool?
    private var lastMuted: Bool?
    private var lastVolume: Float?
    private var lastBrightness: Float?
    private var initialMuted: Bool?

    private func log(_ text: String) {
        print(String(format: "[%6.2f] ", Date().timeIntervalSince(start)) + "[\(phase)] \(text)")
        fflush(stdout)
    }

    private func count(_ signal: String) {
        let key = "\(phase) | \(signal)"
        if counts[key] == nil { order.append(key) }
        counts[key, default: 0] += 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in self?.finish() }
            source.resume()
            signalSources.append(source)
        }

        initialMuted = outputMuted()
        lastMuted = initialMuted
        lastVolume = outputVolume()
        lastBrightness = screenBrightness()
        lastLit = Panel.isLit
        log("start: panel \(lastLit == true ? "lit" : "dark"), muted \(initialMuted.map { "\($0)" } ?? "?"), volume \(lastVolume.map { String(format: "%.2f", $0) } ?? "?"), screen brightness \(lastBrightness.map { String(format: "%.2f", $0) } ?? "?")")

        Panel.onStatusChange { raw in
            DispatchQueue.main.async { [weak self] in
                self?.log("DFR status callback: \(raw)")
                self?.count("DFR status callback")
            }
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer

        showHUD()
        setStep("Get ready.\nHands off the keyboard and trackpad.", seconds: 20,
                say: "Touch Bar test. Hands off the keyboard and trackpad. Starting in twenty seconds.")
        at(20) { self.beginPhase("1 dark+cover", dark: true, cover: true, seconds: 30,
                                 text: "STEP 1 of 3: the bar is dark.\nTap anywhere on the Touch Bar 5 times, slowly.",
                                 say: "Step one. The bar is dark. Tap anywhere on it, five times, slowly.") }
        at(50) { self.beginPhase("2 dark, buttons live", dark: true, cover: false, seconds: 30,
                                 text: "STEP 2 of 3: still dark.\nTap where MUTE is, 2 times, slowly.",
                                 say: "Step two. Still dark. Tap where mute is, two times, slowly.") }
        at(80) { self.beginPhase("3 lit", dark: false, cover: false, seconds: 30,
                                 text: "STEP 3 of 3: nudge the trackpad once,\nthen tap MUTE 2 times and slide VOLUME.",
                                 say: "Step three. Nudge the trackpad once, then tap mute two times, and slide the volume.") }
        at(110) { self.finish() }
    }

    private func at(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }

    // MARK: Prompts: a floating on-screen window plus speech

    private var speech: [Process] = []
    private var hud: NSPanel?
    private let hudText = NSTextField(wrappingLabelWithString: "")
    private let hudCountdown = NSTextField(labelWithString: "")
    private var stepEnds = Date()

    private func speak(_ text: String) {
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = [text]
        say.terminationHandler = { [weak self] p in
            DispatchQueue.main.async { self?.log("speech finished (status \(p.terminationStatus))") }
        }
        do { try say.run(); speech.append(say) } catch { log("speech failed: \(error.localizedDescription)") }
    }

    private func showHUD() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 190),
                            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .hudWindow],
                            backing: .buffered, defer: false)
        panel.title = "Touch Bar test"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        hudText.font = .systemFont(ofSize: 24, weight: .semibold)
        hudText.alignment = .center
        hudText.preferredMaxLayoutWidth = 560
        hudCountdown.font = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        hudCountdown.alignment = .center
        hudCountdown.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [hudText, hudCountdown])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = stack
        panel.center()
        panel.orderFrontRegardless()
        hud = panel

        let tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let left = max(0, Int(ceil(self.stepEnds.timeIntervalSinceNow)))
            self.hudCountdown.stringValue = self.finished ? "" : "Next step in \(left) s"
        }
        RunLoop.main.add(tick, forMode: .common)
    }

    private func setStep(_ text: String, seconds: Double, say: String?) {
        hudText.stringValue = text
        stepEnds = Date().addingTimeInterval(seconds)
        if let say = say { speak(say) }
    }

    private func beginPhase(_ name: String, dark: Bool, cover: Bool, seconds: Double, text: String, say: String) {
        phase = name
        self.dark = dark
        if cover { showCover() } else { hideCover() }
        Panel.set(on: !dark)
        setStep(text, seconds: seconds, say: say)
        log("---- phase start (panel \(dark ? "off" : "on"), cover \(cover ? "on" : "off"))")
    }

    private func showCover() {
        hideCover()
        let view = TouchLogView(frame: .zero)
        view.report = { [weak self] what in
            self?.log(what)
            self?.count(what)
        }
        let item = NSCustomTouchBarItem(identifier: .init("io.github.LeshawnG.Blackout.test"))
        item.view = view
        let newBar = NSTouchBar()
        newBar.templateItems = [item]
        newBar.defaultItemIdentifiers = [item.identifier]
        Panel.hideCloseBox()
        NSTouchBar.presentSystemModalTouchBar(newBar, placement: 1, systemTrayItemIdentifier: .init("io.github.LeshawnG.Blackout.testtray"))
        bar = newBar
    }

    private func hideCover() {
        if let old = bar {
            NSTouchBar.dismissSystemModalTouchBar(old)
            bar = nil
        }
    }

    private func poll() {
        let idle = inputIdleSeconds()
        if idle + 0.03 < lastIdle {
            count("input event (idle reset)")
            // macOS keeps an idle Touch Bar dark; the trackpad nudge in step 3 lets us light it.
            if !dark, phase.hasPrefix("3"), Panel.isLit == false { Panel.set(on: true) }
            if Date().timeIntervalSince(lastIdleLog) > 0.5 {
                log("input event (idle reset)")
                lastIdleLog = Date()
            }
        }
        lastIdle = idle

        let lit = Panel.isLit
        if lit != lastLit {
            log("panel is now \(lit == true ? "LIT" : "dark")")
            if lit == true { count("panel woke") }
            lastLit = lit
            if dark, lit == true {
                // Leave it lit briefly so a tap can land, then darken again for the next tap.
                at(0.5) {
                    guard self.dark, Panel.isLit == true else { return }
                    Panel.set(on: false)
                    self.log("re-darkened panel")
                }
            }
        }

        let muted = outputMuted()
        if muted != lastMuted {
            log("MUTE changed -> \(muted.map { "\($0)" } ?? "?")")
            count("mute toggled")
            lastMuted = muted
        }

        if let v = outputVolume(), let last = lastVolume, abs(v - last) > 0.005 {
            log(String(format: "VOLUME changed -> %.2f", v))
            count("volume changed")
            lastVolume = v
        }

        if let b = screenBrightness(), let last = lastBrightness, abs(b - last) > 0.005 {
            log(String(format: "screen BRIGHTNESS changed -> %.2f", b))
            count("brightness changed")
            lastBrightness = b
        }
    }

    private var finished = false

    private func finish() {
        guard !finished else { return }
        finished = true
        poller?.invalidate()
        phase = "done"
        dark = false
        hideCover()
        Panel.set(on: true)
        if let initial = initialMuted, outputMuted() != initial {
            setOutputMuted(initial)
            log("restored mute to \(initial)")
        }
        setStep("Done, thanks!\nThe Touch Bar is back to normal.", seconds: 0, say: "Done. Thank you.")
        log("SUMMARY")
        for key in order { print("  \(key): \(counts[key] ?? 0)") }
        if order.isEmpty { print("  (no signals recorded)") }
        fflush(stdout)
        at(3) { exit(0) }
    }
}
