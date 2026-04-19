// AppDelegate.swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotKeyManager: HotKeyManager?

    let speechRecognizer = SpeechRecognizer()

    /// The app that was frontmost when the popover was opened — paste target.
    private var previousApp: NSRunningApplication?

    // MARK: – Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupHotKey()
        registerNotifications()
    }

    // MARK: – Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        let img = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "WisperBar")
        img?.isTemplate = true
        button.image = img
        button.action = #selector(handleStatusItemClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        let content = PopoverView().environmentObject(speechRecognizer)
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

    // MARK: – Paste coordination
    //
    // When the popover is open, WisperBar owns the keyboard focus.
    // To paste into the user's real app we must:
    //   1. Close the popover (starts ~200 ms close animation)
    //   2. Explicitly re-activate the app that was frontmost before we stole focus
    //   3. Wait a small extra moment for it to become key
    //   4. Send Cmd+V

    @objc private func handleReadyToPaste() {
        let target = previousApp          // the app to paste into
        popover?.performClose(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Re-activate the target app so it owns the keyboard
            target?.activate(options: .activateIgnoringOtherApps)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.speechRecognizer.pasteToActiveApp()
            }
        }
    }

    // MARK: – Actions

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: speechRecognizer.recordingState == .recording
                ? "Aufnahme stoppen" : "Aufnahme starten",
            action: #selector(toggleRecordingFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
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
            // Capture frontmost app BEFORE we steal focus
            previousApp = NSWorkspace.shared.frontmostApplication
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func activateViaHotKey() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == false {
            // Capture frontmost app BEFORE opening the popover
            previousApp = NSWorkspace.shared.frontmostApplication
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
        speechRecognizer.toggle()
    }

    @objc private func closePopover() {
        popover?.performClose(nil)
    }
}
