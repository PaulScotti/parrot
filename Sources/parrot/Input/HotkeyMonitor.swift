import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Watches a single modifier key and emits press/release edges.
/// Requires Accessibility permission. If the tap fails to register, callers
/// will see an error from `start()`.
final class HotkeyMonitor {
    enum Event {
        case recordingStarted
        case recordingStopped
        case handsFreeStarted
    }
    enum HotkeyError: Error { case tapCreateFailed }

    private let hotkey: Hotkey
    private let debug: Bool
    private var onEvent: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var isSuppressingKeyEvents = false
    private var releasePollTimer: DispatchSourceTimer?
    private var backslashActivation = BackslashActivation()
    private var tapTimeoutGeneration = 0
    private let doubleTapWindow: TimeInterval = 0.40

    init(hotkey: Hotkey, debug: Bool = false) {
        self.hotkey = hotkey
        self.debug = debug
    }

    func start(onEvent: @escaping (Event) -> Void) throws {
        self.onEvent = onEvent

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if !trusted {
            FileHandle.standardError.write(Data(
                "accessibility not granted — system prompt opened. Grant access, then quit and relaunch parrot.\n".utf8
            ))
            throw HotkeyError.tapCreateFailed
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // .cgSessionEventTap is the right level for an accessibility-granted
        // user process (.cghidEventTap requires root).
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: hotkey.suppressesKeyEvents ? .defaultTap : .listenOnly,
                eventsOfInterest: mask,
                callback: hotkeyCallback,
                userInfo: userInfo
            )
        else {
            throw HotkeyError.tapCreateFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        stopReleasePolling()
        tapTimeoutGeneration += 1
        backslashActivation.reset()
        isPressed = false
        onEvent = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if debug {
            let flags = event.flags
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            FileHandle.standardError.write(
                Data(
                    "  [debug] type=\(type.rawValue) keycode=\(keycode) flags=\(String(flags.rawValue, radix: 16))\n"
                        .utf8
                ))
        }
        if let expectedKeycode = hotkey.keycode {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keycode == expectedKeycode else { return }
        }

        let pressed: Bool
        if let modifierMask = hotkey.modifierMask {
            guard type == .flagsChanged else { return }
            pressed = event.flags.contains(modifierMask)
        } else {
            guard type == .keyDown || type == .keyUp else { return }
            guard type == .keyUp || !hasShortcutModifiers(event.flags) else { return }
            pressed = type == .keyDown
        }

        transition(to: pressed)
    }

    /// Active event taps can occasionally miss a key-up after suppressing a
    /// printable key. Poll the HID state while Backslash is held so recording
    /// always ends when the physical key is released.
    private func startReleasePolling() {
        guard releasePollTimer == nil, let keycode = hotkey.keycode else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(25),
            repeating: .milliseconds(25),
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let isDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keycode))
            if !isDown {
                self.transition(to: false)
            }
        }
        releasePollTimer = timer
        timer.resume()
    }

    private func stopReleasePolling() {
        releasePollTimer?.cancel()
        releasePollTimer = nil
    }

    private func transition(to pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        if pressed, hotkey.modifierMask == nil {
            startReleasePolling()
        } else if !pressed {
            stopReleasePolling()
        }
        handleActivationEdge(pressed: pressed)
    }

    private func handleActivationEdge(pressed: Bool) {
        // Double-tap latching is intentionally limited to Backslash. Modifier
        // hotkeys retain their exact push-to-talk behavior.
        guard hotkey == .backslash else {
            onEvent?(pressed ? .recordingStarted : .recordingStopped)
            return
        }

        tapTimeoutGeneration += 1
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        let action = backslashActivation.handle(pressed: pressed, at: now)
        if backslashActivation.state == .waitingForSecondTap {
            scheduleSingleTapStop(generation: tapTimeoutGeneration)
        }
        emit(action)
    }

    private func scheduleSingleTapStop(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow) { [weak self] in
            guard let self,
                  self.tapTimeoutGeneration == generation else { return }
            self.emit(self.backslashActivation.singleTapTimedOut())
        }
    }

    private func emit(_ action: BackslashActivation.Action?) {
        switch action {
        case .startRecording:
            onEvent?(.recordingStarted)
        case .stopRecording:
            onEvent?(.recordingStopped)
        case .handsFreeStarted:
            onEvent?(.handsFreeStarted)
        case nil:
            break
        }
    }

    fileprivate func reenableTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// A printable push-to-talk key should not hijack Command/Option/Control
    /// shortcuts or Shift-Backslash (the pipe character).
    fileprivate func shouldSuppress(type: CGEventType, event: CGEvent) -> Bool {
        guard hotkey.suppressesKeyEvents, type == .keyDown || type == .keyUp else {
            return false
        }
        guard let keycode = hotkey.keycode,
              event.getIntegerValueField(.keyboardEventKeycode) == keycode else {
            return false
        }
        if type == .keyDown {
            if isSuppressingKeyEvents { return true }
            let suppress = !hasShortcutModifiers(event.flags)
            if suppress { isSuppressingKeyEvents = true }
            return suppress
        }

        let suppress = isSuppressingKeyEvents
        isSuppressingKeyEvents = false
        return suppress
    }

    private func hasShortcutModifiers(_ flags: CGEventFlags) -> Bool {
        let shortcutFlags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        return !flags.intersection(shortcutFlags).isEmpty
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    let suppress = monitor.shouldSuppress(type: type, event: event)
    let copy = event.copy()
    DispatchQueue.main.async {
        if let copy {
            monitor.handle(type: type, event: copy)
        }
    }
    if suppress {
        // Keep the hardware event sequence intact so macOS still delivers the
        // matching key-up, but turn the printable event into a harmless null
        // event before it reaches the focused application.
        event.type = .null
    }
    return Unmanaged.passUnretained(event)
}
