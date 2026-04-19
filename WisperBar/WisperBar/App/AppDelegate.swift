// AppDelegate.swift
// Verwaltet NSStatusItem (Menüleisten-Icon) und NSPopover.
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: – Eigenschaften

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotKeyManager: HotKeyManager?

    /// Gemeinsames Modell – wird per EnvironmentObject weitergegeben
    let speechRecognizer = SpeechRecognizer()

    // MARK: – App-Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App nicht im Dock anzeigen
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupHotKey()
        registerNotifications()
    }

    // MARK: – Aufbau

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }
        // SF Symbol als Template-Image (passt sich Dark/Light Mode an)
        let img = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "WisperBar")
        img?.isTemplate = true
        button.image = img
        button.action = #selector(handleStatusItemClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        let content = PopoverView()
            .environmentObject(speechRecognizer)

        let pop = NSPopover()
        pop.contentViewController = NSHostingController(rootView: content)
        pop.contentSize = NSSize(width: 560, height: 640)
        pop.behavior = .transient
        pop.animates = true
        self.popover = pop
    }

    private func setupHotKey() {
        hotKeyManager = HotKeyManager()
        hotKeyManager?.register { [weak self] in
            DispatchQueue.main.async { self?.activateViaHotKey() }
        }
    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(closePopover),
            name: .wbClosePopover, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleReadyToPaste),
            name: .wbReadyToPaste, object: nil
        )
    }

    /// Cierra el popover para que la app de fondo recupere el foco, luego pega.
    @objc private func handleReadyToPaste() {
        popover?.performClose(nil)
        // 650 ms gives macOS enough time to close the popover animation
        // and return keyboard focus to the previously active app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            self?.speechRecognizer.pasteToActiveApp()
        }
    }

    // MARK: – Aktionen

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: speechRecognizer.recordingState == .recording ? "Aufnahme stoppen" : "Aufnahme starten",
            action: #selector(toggleRecordingFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Menü-Referenz danach entfernen, damit linker Klick wieder den Popover öffnet
        DispatchQueue.main.async { self.statusItem?.menu = nil }
    }

    @objc private func toggleRecordingFromMenu() {
        speechRecognizer.toggle()
    }

    func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let pop = popover, pop.isShown {
            pop.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Wird vom globalen Hotkey aufgerufen
    private func activateViaHotKey() {
        guard let button = statusItem?.button else { return }

        // Popover öffnen falls nötig
        if popover?.isShown == false {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }

        // Aufnahme umschalten
        speechRecognizer.toggle()
    }

    @objc private func closePopover() {
        popover?.performClose(nil)
    }
}
