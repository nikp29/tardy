import AppKit
import SwiftUI

final class MenuBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let settings: SettingsManager
    private let soundPlayer: SoundPlayer
    private var nextEvent: UpcomingEvent?

    init(settings: SettingsManager, soundPlayer: SoundPlayer) {
        self.settings = settings
        self.soundPlayer = soundPlayer
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Tardy")
        }
        statusItem = item
        rebuildMenu()
    }

    func updateNextEvent(_ event: UpcomingEvent?) {
        nextEvent = event
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let event = nextEvent {
            let time = event.startDate.formatted(date: .omitted, time: .shortened)
            let info = NSMenuItem(title: "Next: \(event.title) at \(time)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        } else {
            let info = NSMenuItem(title: "No upcoming events", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Tardy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Clean up old window completely before creating new one
        settingsWindow?.contentView = nil
        settingsWindow?.close()
        settingsWindow = nil

        let view = SettingsView(settings: settings, soundPlayer: soundPlayer)
        let hostingView = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Tardy Settings"
        win.contentView = hostingView
        win.delegate = self
        win.center()
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.backgroundColor = NSColor(red: 22/255, green: 22/255, blue: 32/255, alpha: 0.98)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = win
    }

    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win === settingsWindow {
            settingsWindow?.contentView = nil
            settingsWindow = nil
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
