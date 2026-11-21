// The Touch Bar panel: power, status and brightness, through Apple's private frameworks.
//
//   DFRBrightness  DFRBrightnessClient turnOff/turnOn: the switch macOS itself uses when the
//                  Touch Bar goes dark after you stop typing.
//   DFRFoundation  panel status (DFRGetStatus) and status-change notifications.
//   CoreBrightness the panel's current brightness (read only).
//
// Everything is looked up at runtime, so a macOS update that removes something makes the
// matching feature unavailable rather than crashing the app.

import AppKit

enum Panel {
    private static let foundation = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
    private static let dfrBrightness = dlopen("/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness", RTLD_NOW)
    private static let coreBrightness = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
    private static let darkBit = 0x4

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let foundation = foundation else { return nil }
        return dlsym(foundation, name)
    }

    /// One DFRBrightnessClient for the whole run. Each one opens its own CoreBrightness
    /// connection and keeps itself alive after its last reference is gone, so 1.0.0, which
    /// made a new one per call, had 2,529 of them alive after 4.5 days.
    private static var cachedClient: NSObject?

    private static var client: NSObject? {
        if let client = cachedClient { return client }
        guard dfrBrightness != nil, let cls = NSClassFromString("DFRBrightnessClient") as? NSObject.Type else { return nil }
        let client = cls.init()
        cachedClient = client
        return client
    }

    /// Next call gets a new client (after a failed call, or for Force Restore).
    /// The old one stays alive (see above), so this is for rare use only.
    static func resetClient() { cachedClient = nil }

    /// A long-lived client may cache the panel state; drop that before acting on it.
    private static func flushCache(_ client: NSObject) {
        let selector = NSSelectorFromString("flushPropertyCache")
        guard client.responds(to: selector) else { return }
        typealias Flush = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(client.method(for: selector), to: Flush.self)(client, selector)
    }

    static var isAvailable: Bool {
        guard let client = client, symbol("DFRGetStatus") != nil else { return false }
        return client.responds(to: NSSelectorFromString("turnOffWithPeriod:"))
            && client.responds(to: NSSelectorFromString("turnOnWithPeriod:"))
    }

    /// Raw DFRGetStatus value; bit 0x4 set = panel dark. nil when it can't be read.
    static var rawStatus: Int? {
        guard let sym = symbol("DFRGetStatus") else { return nil }
        typealias GetStatus = @convention(c) () -> Int
        return unsafeBitCast(sym, to: GetStatus.self)()
    }

    /// nil when the status can't be read.
    static var isLit: Bool? { rawStatus.map { $0 & darkBit == 0 } }

    /// Switches the panel on or off. A zero period skips the fade, so the panel never
    /// passes through the low brightness levels where faulty panels flicker.
    /// If the call fails, it is tried once more with a new client.
    @discardableResult
    static func set(on: Bool) -> Bool {
        if send(on: on) { return true }
        resetClient()
        return send(on: on)
    }

    private static func send(on: Bool) -> Bool {
        guard let client = client else { return false }
        flushCache(client)
        let withPeriod = NSSelectorFromString(on ? "turnOnWithPeriod:" : "turnOffWithPeriod:")
        if client.responds(to: withPeriod) {
            typealias Call = @convention(c) (AnyObject, Selector, Float) -> Bool
            let call = unsafeBitCast(client.method(for: withPeriod), to: Call.self)
            if call(client, withPeriod, 0) { return true }
        }
        let plain = NSSelectorFromString(on ? "turnOn" : "turnOff")
        guard client.responds(to: plain) else { return false }
        typealias Plain = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(client.method(for: plain), to: Plain.self)(client, plain)
    }

    static func onStatusChange(_ handler: @escaping @convention(block) (Int) -> Void) {
        guard let sym = symbol("DFRRegisterStatusChangeCallback") else { return }
        typealias Register = @convention(c) (@convention(block) (Int) -> Void) -> Void
        unsafeBitCast(sym, to: Register.self)(handler)
    }

    static func hideCloseBox() {
        guard let sym = symbol("DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        typealias SetBool = @convention(c) (Bool) -> Void
        unsafeBitCast(sym, to: SetBool.self)(false)
    }

    // MARK: Brightness and diagnostics (read only)

    private static var displayID: UInt64? {
        guard let client = client else { return nil }
        let selector = NSSelectorFromString("getDFRDisplayID")
        guard client.responds(to: selector) else { return nil }
        typealias GetID = @convention(c) (AnyObject, Selector) -> UInt32
        return UInt64(unsafeBitCast(client.method(for: selector), to: GetID.self)(client, selector))
    }

    private static let brightnessClient: NSObject? = {
        guard coreBrightness != nil, let cls = NSClassFromString("BrightnessSystemClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    /// The panel's brightness as macOS reports it: `level` 0–1 within the Touch Bar's range
    /// (0 is its dimmest lit setting, not off) and the light output in nits.
    static var brightness: (level: Float, nits: Float?, physicalNits: Float?)? {
        guard let client = brightnessClient, let id = displayID else { return nil }
        let selector = NSSelectorFromString("copyPropertyForKey:andDisplay:")
        guard client.responds(to: selector) else { return nil }
        typealias Copy = @convention(c) (AnyObject, Selector, NSString, UInt64) -> Unmanaged<AnyObject>?
        let copy = unsafeBitCast(client.method(for: selector), to: Copy.self)
        guard let dict = copy(client, selector, "DisplayBrightness", id)?.takeRetainedValue() as? [String: Any] else { return nil }
        func number(_ key: String) -> Float? {
            if let n = dict[key] as? NSNumber { return n.floatValue }
            if let s = dict[key] as? String { return Float(s) }
            return nil
        }
        guard let level = number("Brightness") else { return nil }
        return (level, number("Nits"), number("NitsPhysical"))
    }

    private static func setProperty(_ value: NSNumber, forKey key: String) -> Bool {
        guard let client = brightnessClient, let id = displayID else { return false }
        let selector = NSSelectorFromString("setProperty:withKey:andDisplay:")
        guard client.responds(to: selector) else { return false }
        typealias Set = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool
        return unsafeBitCast(client.method(for: selector), to: Set.self)(client, selector, value, key as NSString, id)
    }

    /// Sets the Touch Bar's brightness `level` (0–1, as in `brightness`) through CoreBrightness.
    /// Used only when auto-brightness is off (see `recheckAutoBrightness`).
    @discardableResult
    static func setBrightness(_ level: Float) -> Bool {
        setProperty(NSNumber(value: level), forKey: "DisplayBrightness")
    }

    /// Whether macOS auto-brightness is on for the Touch Bar (CoreBrightness `DisplayBrightnessAuto`).
    static var autoBrightness: Bool? {
        guard let client = brightnessClient, let id = displayID else { return nil }
        let selector = NSSelectorFromString("copyPropertyForKey:andDisplay:")
        guard client.responds(to: selector) else { return nil }
        typealias Copy = @convention(c) (AnyObject, Selector, NSString, UInt64) -> Unmanaged<AnyObject>?
        let copy = unsafeBitCast(client.method(for: selector), to: Copy.self)
        return (copy(client, selector, "DisplayBrightnessAuto", id)?.takeRetainedValue() as? NSNumber)?.boolValue
    }

    /// Switching the panel off and on leaves its brightness at the bottom of its range (about
    /// 12 nits), and macOS doesn't re-check the light sensor until the screen next wakes.
    /// Turning the Touch Bar's auto-brightness off and straight back on makes it re-check:
    /// it fades the bar to the right level for the room in about half a second.
    /// Both calls run back to back, so auto-brightness is never left off.
    @discardableResult
    static func recheckAutoBrightness() -> Bool {
        let off = setProperty(NSNumber(value: 0), forKey: "DisplayBrightnessAuto")
        let on = setProperty(NSNumber(value: 1), forKey: "DisplayBrightnessAuto")
        return off && on
    }

    /// Integer getters on the DFR client (displayState, getDimmingStep, harmonyState).
    private static func clientInt(_ name: String) -> Int? {
        guard let client = client else { return nil }
        let selector = NSSelectorFromString(name)
        guard client.responds(to: selector) else { return nil }
        typealias Get = @convention(c) (AnyObject, Selector) -> Int
        return unsafeBitCast(client.method(for: selector), to: Get.self)(client, selector)
    }

    /// Everything readable about the panel, for the log and `Blackout diag`. Getters only.
    struct Reading {
        var status: Int?
        var displayState: Int?
        var dimmingStep: Int?
        var harmonyState: Int?
        var brightness: (level: Float, nits: Float?, physicalNits: Float?)?

        var isLit: Bool? { status.map { $0 & Panel.darkBit == 0 } }

        /// Lit, but CoreBrightness says it gives out no light: the "dark but touchable" case.
        var looksDarkWhileLit: Bool {
            guard isLit == true, let b = brightness else { return false }
            return (b.physicalNits ?? b.nits ?? 1) < 0.5
        }

        var text: String {
            func s(_ v: Int?) -> String { v.map(String.init) ?? "?" }
            func f(_ v: Float?) -> String { v.map { String(format: "%.1f", $0) } ?? "?" }
            let lit = isLit.map { $0 ? "lit" : "dark" } ?? "?"
            return "\(lit) status=\(status.map { String(format: "0x%lx", $0) } ?? "?")"
                + " displayState=\(s(displayState)) dimStep=\(s(dimmingStep)) harmony=\(s(harmonyState))"
                + " brightness=\(brightness.map { String(format: "%.0f%%", $0.level * 100) } ?? "?")"
                + " nits=\(f(brightness?.nits)) physical=\(f(brightness?.physicalNits))"
        }
    }

    static func reading() -> Reading {
        if let client = client { flushCache(client) }
        return Reading(status: rawStatus,
                       displayState: clientInt("displayState"),
                       dimmingStep: clientInt("getDimmingStep"),
                       harmonyState: clientInt("harmonyState"),
                       brightness: brightness)
    }
}
