//
//  HotkeyManager.swift
//  Screenshot
//
//  Global hotkey registration (lightweight monitor placeholder for MVP).
//

import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    static let shared = HotkeyManager()

    struct KeyCombo: Equatable {
        var keyCode: UInt16
        var modifiers: NSEvent.ModifierFlags
    }

    private var monitor: Any?
    private var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Default: Cmd+Shift+8 (non-conflicting commonly)
    private let defaultCombo = KeyCombo(keyCode: 28 /* '8' */, modifiers: [.command, .shift])

    func registerDefaultHotkey(_ handler: @escaping () -> Void) {
        register(combo: defaultCombo, handler: handler)
    }

    func register(combo: KeyCombo, handler: @escaping () -> Void) {
        self.handler = handler
        // Remove existing monitor if present
        if let m = monitor { NSEvent.removeMonitor(m) }

        // Try Carbon global hotkey first
        if registerCarbonHotKey(combo: combo) {
            return
        }
        // Fallback: global monitor
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let cleanMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if cleanMods == combo.modifiers && event.keyCode == combo.keyCode {
                self.handler?()
            }
        }
    }

    func unregister() {
        if let hk = hotKeyRef { UnregisterEventHotKey(hk) }
        if let eh = eventHandlerRef { RemoveEventHandler(eh) }
        hotKeyRef = nil
        eventHandlerRef = nil
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        handler = nil
    }

    deinit { unregister() }

    private func registerCarbonHotKey(combo: KeyCombo) -> Bool {
        // Map NSEvent.ModifierFlags to Carbon modifiers
        var mods: UInt32 = 0
        if combo.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if combo.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        if combo.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if combo.modifiers.contains(.control) { mods |= UInt32(controlKey) }

        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(bitPattern: Int32("SHOT".utf8.reduce(0) { ($0 << 8) | Int($1) }))), id: 1)
        let status = RegisterEventHotKey(UInt32(combo.keyCode), mods, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else { return false }

        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { (_, eventRef, userData) in
            let mySelf = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            mySelf.handler?()
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), callback, 1, [eventSpec], selfPtr, &handlerRef)
        guard installStatus == noErr, let handlerRef = handlerRef else { return false }
        self.eventHandlerRef = handlerRef
        return true
    }
}
