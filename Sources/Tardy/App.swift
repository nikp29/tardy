import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate, CalendarServiceDelegate {
    private let settings = SettingsManager()
    private var calendarService: CalendarService!
    private var alertScheduler: AlertScheduler!
    private var alertWindowController = AlertWindowController()
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(settings: settings)
        menuBarController.setup()

        alertScheduler = AlertScheduler(settings: settings) { [weak self] event in
            DispatchQueue.main.async {
                self?.showAlert(for: event)
            }
        }

        calendarService = CalendarService()
        calendarService.delegate = self
        calendarService.start()
    }

    // MARK: - CalendarServiceDelegate

    func calendarService(_ service: CalendarService, didUpdateEvents events: [UpcomingEvent]) {
        DispatchQueue.main.async { [weak self] in
            self?.alertScheduler.updateEvents(events)

            let nextEvent = events
                .filter { $0.startDate > Date() }
                .sorted(by: { $0.startDate < $1.startDate })
                .first
            self?.menuBarController.updateNextEvent(nextEvent)
        }
    }

    // MARK: - Alert presentation

    private func showAlert(for event: UpcomingEvent) {
        alertWindowController.onDismiss = { _ in }
        alertWindowController.onSnooze = { [weak self] event in
            self?.alertScheduler.snooze(event: event)
        }
        alertWindowController.show(event: event)
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
