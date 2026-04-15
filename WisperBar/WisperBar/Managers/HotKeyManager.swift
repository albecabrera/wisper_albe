// HotKeyManager.swift
// Registriert einen systemweiten Keyboard-Shortcut via Carbon-Framework.
// Carbon-Hotkeys funktionieren ohne Accessibility-Berechtigung.
import Carbon
import AppKit

final class HotKeyManager {

    // MARK: – Konfiguration

    /// Standard-Shortcut: ⌘⇧D
    /// Kann durch Anpassen von `keyCode` und `modifiers` geändert werden.
    private let keyCode:   UInt32 = UInt32(kVK_ANSI_D)
    private let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

    // MARK: – Private Eigenschaften

    private var hotKeyRef:      EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Statische Referenz auf die Callback-Closure, da C-Funktionszeiger keinen
    /// Swift-Kontext einschließen können.
    nonisolated(unsafe) static var onHotKeyPressed: (() -> Void)?

    // MARK: – Öffentliche API

    /// Shortcut registrieren und Callback hinterlegen.
    func register(callback: @escaping () -> Void) {
        HotKeyManager.onHotKeyPressed = callback
        installEventHandler()
        registerHotKey()
    }

    // MARK: – Carbon-Integration

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  OSType(kEventHotKeyPressed)
        )

        // C-kompatibler Handler ohne Swift-Kontext-Capture
        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            HotKeyManager.onHotKeyPressed?()
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            print("[WisperBar] HotKey-EventHandler konnte nicht installiert werden: \(status)")
        }
    }

    private func registerHotKey() {
        // Eindeutige ID für diesen Hotkey ("WBRK" als 4-char-code)
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = fourCharCode("WBRK")
        hotKeyID.id = 1

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )

        if status != noErr {
            print("[WisperBar] Hotkey konnte nicht registriert werden: \(status)")
        } else {
            print("[WisperBar] Hotkey ⌘⇧D erfolgreich registriert.")
        }
    }

    /// Konvertiert einen 4-Zeichen-String in einen OSType (FourCharCode)
    private func fourCharCode(_ s: String) -> OSType {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) | OSType($1) }
    }

    // MARK: – Aufräumen

    deinit {
        if let ref = hotKeyRef      { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        HotKeyManager.onHotKeyPressed = nil
    }
}
