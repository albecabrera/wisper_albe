// WisperBarApp.swift
// Einstiegspunkt der App – nutzt AppDelegate für Menüleisten-Logik
import SwiftUI

@main
struct WisperBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Leere Settings-Scene verhindert, dass die App automatisch beendet wird,
        // wenn das letzte Fenster geschlossen wird.
        Settings { EmptyView() }
    }
}
