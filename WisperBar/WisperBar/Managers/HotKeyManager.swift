// HotKeyManager.swift
// Erkennt den globalen Shortcut fn+Shift via NSEvent.flagsChanged.
// Kein Carbon nötig – kein separater API-Key oder Accessibility-Berechtigung
// für reine Modifier-Kombinationen.
import AppKit

final class HotKeyManager {

    // MARK: – Eigenschaften

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Zuletzt gesehener Modifier-Zustand (für Edge-Detection: "gerade gedrückt")
    private var previousFlags: NSEvent.ModifierFlags = []

    // Statisch, damit Callback aus dem Monitor-Block erreichbar ist
    nonisolated(unsafe) static var onActivate: (() -> Void)?

    // MARK: – Öffentliche API

    /// fn+Shift-Monitor registrieren.
    func register(callback: @escaping () -> Void) {
        HotKeyManager.onActivate = callback
        installMonitors()
    }

    // MARK: – Monitor-Setup

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Global: greift wenn eine andere App im Vordergrund ist
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
        }

        // Lokal: greift wenn der Popover fokussiert ist
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    /// Wertet aus ob fn+Shift soeben aktiviert wurde (rising edge).
    private func handleFlagsChanged(_ event: NSEvent) {
        // Nur die für uns relevanten Modifier betrachten
        let relevant: NSEvent.ModifierFlags = [.function, .shift, .command, .option, .control]
        let current = event.modifierFlags.intersection(relevant)

        // fn+Shift = genau .function und .shift, keine anderen Modifier
        let target: NSEvent.ModifierFlags = [.function, .shift]
        let isActive   = current == target
        let wasActive  = previousFlags == target

        // Rising-Edge: fn+Shift gerade aktiviert (nicht schon vorher gehalten)
        if isActive && !wasActive {
            HotKeyManager.onActivate?()
        }

        previousFlags = current
    }

    // MARK: – Aufräumen

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        HotKeyManager.onActivate = nil
    }
}
