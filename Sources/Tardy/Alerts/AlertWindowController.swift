import AppKit
import SwiftUI

final class AlertWindowController {
    private var window: NSWindow?
    var onDismiss: ((UpcomingEvent) -> Void)?
    var onSnooze: ((UpcomingEvent) -> Void)?

    func show(event: UpcomingEvent) {
        guard let screen = NSScreen.main else { return }

        let contentView = AlertContentView(
            event: event,
            onDismiss: { [weak self] in self?.dismiss(event: event) },
            onSnooze: { [weak self] in self?.snooze(event: event) },
            onJoinCall: { [weak self] url in self?.openURL(url, event: event) },
            onDialPhone: { [weak self] phone in self?.dialPhone(phone, event: event) }
        )

        let hostingView = NSHostingView(rootView: contentView)

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false

        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            win.animator().alphaValue = 1
        }

        self.window = win
    }

    private func dismiss(event: UpcomingEvent) {
        animateOut {
            self.onDismiss?(event)
        }
    }

    private func snooze(event: UpcomingEvent) {
        animateOut {
            self.onSnooze?(event)
        }
    }

    private func openURL(_ url: URL, event: UpcomingEvent) {
        NSWorkspace.shared.open(url)
        animateOut {
            self.onDismiss?(event)
        }
    }

    private func dialPhone(_ phone: String, event: UpcomingEvent) {
        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
            NSWorkspace.shared.open(url)
        }
        animateOut {
            self.onDismiss?(event)
        }
    }

    private func animateOut(completion: @escaping () -> Void) {
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
            self.window = nil
            completion()
        })
    }
}

// MARK: - SwiftUI Alert View

struct AlertContentView: View {
    let event: UpcomingEvent
    let onDismiss: () -> Void
    let onSnooze: () -> Void
    let onJoinCall: (URL) -> Void
    let onDialPhone: (String) -> Void

    @State private var countdown: TimeInterval = 0
    @State private var countdownTimer: Timer?

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text(event.title)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.7))
                }

                if countdown > 0 {
                    Text("Starts in \(formattedCountdown)")
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                }

                if let url = event.conferenceURL {
                    Button(action: { onJoinCall(url) }) {
                        Text("Join Meeting")
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else if let phone = event.phoneNumber {
                    Button(action: { onDialPhone(phone) }) {
                        Text("Dial \(phone)")
                            .font(.system(size: 20))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else if let notes = event.notes, !notes.isEmpty {
                    Text(String(notes.prefix(200)))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                }

                HStack(spacing: 20) {
                    Button(action: onSnooze) {
                        Text("Snooze (2 min)")
                            .font(.system(size: 18))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.system(size: 18))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }
        .onAppear {
            updateCountdown()
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                updateCountdown()
            }
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }

    private func updateCountdown() {
        let remaining = event.startDate.timeIntervalSinceNow
        countdown = max(0, remaining)
    }

    private var formattedCountdown: String {
        let minutes = Int(countdown) / 60
        let seconds = Int(countdown) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
