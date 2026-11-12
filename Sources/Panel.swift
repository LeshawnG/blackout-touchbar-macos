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

    private static var client: NSObject? {
        guard dfrBrightness != nil, let cls = NSClassFromString("DFRBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }

    static var isAvailable: Bool {
        guard let client = client, symbol("DFRGetStatus") != nil else { return false }
        return client.responds(to: NSSelectorFromString("turnOffWithPeriod:"))
            && client.responds(to: NSSelectorFromString("turnOnWithPeriod:"))
    }

    /// nil when the status can't be read.
    static var isLit: Bool? {
        guard let sym = symbol("DFRGetStatus") else { return nil }
        typealias GetStatus = @convention(c) () -> Int
        return unsafeBitCast(sym, to: GetStatus.self)() & darkBit == 0
    }

    /// Switches the panel on or off. A zero period skips the fade, so the panel never
    /// passes through the low brightness levels where faulty panels flicker.
    @discardableResult
    static func set(on: Bool) -> Bool {
        guard let client = client else { return false }
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

    // MARK: Brightness (read only)

    private static var displayID: UInt64? {
        guard let client = client else { return nil }
        let selector = NSSelectorFromString("getDFRDisplayID")
        guard client.responds(to: selector) else { return nil }
        typealias GetID = @convention(c) (AnyObject, Selector) -> UInt32
        return UInt64(unsafeBitCast(client.method(for: selector), to: GetID.self)(client, selector))
    }

    /// The panel's brightness as macOS reports it: `level` 0–1 within the Touch Bar's range
    /// (0 is its dimmest lit setting, not off) and the light output in nits.
    static var brightness: (level: Float, nits: Float?)? {
        guard coreBrightness != nil,
              let cls = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              let id = displayID else { return nil }
        let client = cls.init()
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
        return (level, number("Nits"))
    }
}
