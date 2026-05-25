import AppKit
import SwiftUI

final class MenuBarController: NSObject, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let settings: SettingsManager
    private let soundPlayer: SoundPlayer
    private let googleAuth: GoogleAuthProviding
    private let onGoogleConnected: () -> Void
    private let onGoogleDisconnected: () -> Void
    private let onPollNow: () -> Void
    private var nextEvent: UpcomingEvent?
    private var googleNeedsReauth = false

    init(
        settings: SettingsManager,
        soundPlayer: SoundPlayer,
        googleAuth: GoogleAuthProviding,
        onGoogleConnected: @escaping () -> Void,
        onGoogleDisconnected: @escaping () -> Void,
        onPollNow: @escaping () -> Void
    ) {
        self.settings = settings
        self.soundPlayer = soundPlayer
        self.googleAuth = googleAuth
        self.onGoogleConnected = onGoogleConnected
        self.onGoogleDisconnected = onGoogleDisconnected
        self.onPollNow = onPollNow
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

    /// Called by the Google provider when a token refresh fails.
    func setGoogleNeedsReauth(_ on: Bool) {
        googleNeedsReauth = on
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self // menuWillOpen → poll-on-open

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

        if googleNeedsReauth {
            let reauth = NSMenuItem(title: "Reconnect Google…", action: #selector(openSettings), keyEquivalent: "")
            reauth.target = self
            menu.addItem(reauth)
        }

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Tardy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate (poll-on-open)

    func menuWillOpen(_ menu: NSMenu) {
        onPollNow()
    }

    @objc func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Clean up old window completely before creating new one
        settingsWindow?.contentView = nil
        settingsWindow?.close()
        settingsWindow = nil

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        let model = makeGoogleModel(presentingWindow: win)
        let view = SettingsView(settings: settings, soundPlayer: soundPlayer, google: model)
        let hostingView = NSHostingView(rootView: view)

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

    private func makeGoogleModel(presentingWindow win: NSWindow) -> GoogleConnectionModel {
        let model = GoogleConnectionModel(email: googleAuth.isSignedIn ? googleAuth.accountEmail : nil)
        model.needsReauth = googleNeedsReauth

        model.onConnect = { [weak self, weak win, weak model] in
            guard let self, let win, let model else { return }
            model.isConnecting = true
            Task { @MainActor in
                defer { model.isConnecting = false }
                do {
                    try await self.googleAuth.signIn(presenting: win)
                    model.email = self.googleAuth.accountEmail
                    model.needsReauth = false
                    self.setGoogleNeedsReauth(false)
                    self.onGoogleConnected()
                } catch {
                    // Cancelled or failed: stay disconnected.
                }
            }
        }

        model.onDisconnect = { [weak self, weak model] in
            guard let self else { return }
            self.googleAuth.signOut()
            model?.email = nil
            model?.needsReauth = false
            self.setGoogleNeedsReauth(false)
            self.onGoogleDisconnected()
        }

        return model
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
