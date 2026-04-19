// Notification+Names.swift
// Zentrale Definitionen aller benutzerdefinierten Notification-Namen
import Foundation

extension Notification.Name {
    static let wbClosePopover  = Notification.Name("com.wisperbar.closePopover")
    /// Posted when transcript is ready to paste; AppDelegate closes popover first, then pastes.
    static let wbReadyToPaste  = Notification.Name("com.wisperbar.readyToPaste")
}
