import AppKit
import Foundation
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, EventCoordinatorDelegate {
    private let settings = SettingsManager()
    private let soundPlayer = SoundPlayer()
    private let googleAuth = GoogleSignInAuthService.shared
    private var googleProvider: GoogleCalendarProvider!
    private var eventCoordinator: EventCoordinator!
    private var alertScheduler: AlertScheduler!
    private var alertWindowController = AlertWindowController()
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistration.registerCustomFonts()
        configureLaunchOnLogin()

        menuBarController = MenuBarController(
            settings: settings,
            soundPlayer: soundPlayer,
            googleAuth: googleAuth,
            onGoogleConnected: { [weak self] in
                guard let self else { return }
                self.settings.googleCalendarEnabled = true
                self.googleProvider.setEnabled(true)
                self.eventCoordinator.refresh(forceReschedule: true)
            },
            onGoogleDisconnected: { [weak self] in
                guard let self else { return }
                self.settings.googleCalendarEnabled = false
                self.googleProvider.setEnabled(false)
                self.eventCoordinator.refresh(forceReschedule: true)
            },
            onPollNow: { [weak self] in self?.eventCoordinator.refresh() }
        )
        menuBarController.setup()

        alertScheduler = AlertScheduler(settings: settings) { [weak self] event in
            DispatchQueue.main.async {
                self?.showAlert(for: event)
            }
        }

        googleProvider = GoogleCalendarProvider(auth: googleAuth)
        googleProvider.setEnabled(settings.googleCalendarEnabled)
        googleProvider.onNeedsReauth = { [weak self] in
            DispatchQueue.main.async { self?.menuBarController.setGoogleNeedsReauth(true) }
        }

        eventCoordinator = EventCoordinator(providers: [EventKitProvider(), googleProvider])
        eventCoordinator.delegate = self
        Task { @MainActor in
            await googleAuth.restorePreviousSignIn()
            eventCoordinator.start()
        }

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            menuBarController.openSettings()
        }
    }

    // MARK: - CalendarServiceDelegate

    func eventCoordinator(
        _ coordinator: EventCoordinator,
        didUpdateEvents events: [UpcomingEvent],
        forceReschedule: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.alertScheduler.updateEvents(events, forceReschedule: forceReschedule)

            let nextEvent = events
                .filter { $0.startDate > Date() }
                .sorted(by: { $0.startDate < $1.startDate })
                .first
            self?.menuBarController.updateNextEvent(nextEvent)
        }
    }

    // MARK: - Alert presentation

    private func showAlert(for event: UpcomingEvent) {
        soundPlayer.play(settings.alertSound)

        alertWindowController.onDismiss = { _ in }
        alertWindowController.onSnooze = { [weak self] event in
            self?.alertScheduler.snooze(event: event)
        }
        alertWindowController.show(event: event)
    }

    // MARK: - Login item

    private func configureLaunchOnLogin() {
        let service = SMAppService.mainApp
        if settings.launchOnLogin {
            try? service.register()
        } else {
            try? service.unregister()
        }
    }
}

@main
enum TardyApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
