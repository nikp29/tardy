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
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Blurred dark backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            // Floating card
            VStack(spacing: 12) {
                Text("STARTING SOON")
                    .font(.custom("Instrument Sans", size: 9))
                    .fontWeight(.bold)
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.3))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.15), value: appeared)

                Text(event.title)
                    .font(.custom("Instrument Sans", size: 32))
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.2), value: appeared)

                HStack(spacing: 6) {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                    if let location = event.location, !location.isEmpty {
                        Text("·")
                        Text(location)
                    }
                }
                .font(.custom("Instrument Sans", size: 13))
                .foregroundColor(.white.opacity(0.35))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.25), value: appeared)

                if countdown > 0 {
                    Text(formattedCountdown)
                        .font(.custom("DM Mono", size: 42))
                        .fontWeight(.light)
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(5)
                        .padding(.vertical, 4)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.3), value: appeared)
                }

                conferenceAction
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.35), value: appeared)

                HStack(spacing: 8) {
                    ActionButton(label: "Snooze", subtitle: "2 min", action: onSnooze)
                    ActionButton(label: "Dismiss", subtitle: nil, action: onDismiss)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.4), value: appeared)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
            .frame(maxWidth: 380)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 30/255, green: 30/255, blue: 50/255).opacity(0.75),
                        Color(red: 50/255, green: 50/255, blue: 75/255).opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: appeared)
        }
        .onAppear {
            updateCountdown()
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                updateCountdown()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }

    @ViewBuilder
    private var conferenceAction: some View {
        if let url = event.conferenceURL {
            InteractiveButton(
                label: "Join Meeting",
                bgColor: Color(red: 59/255, green: 130/255, blue: 246/255),
                action: { onJoinCall(url) }
            )
        } else if let phone = event.phoneNumber {
            InteractiveButton(
                label: "Dial \(phone)",
                bgColor: Color(red: 34/255, green: 197/255, blue: 94/255),
                action: { onDialPhone(phone) }
            )
        } else if let notes = event.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES")
                    .font(.custom("Instrument Sans", size: 9))
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.25))
                Text(String(notes.prefix(200)))
                    .font(.custom("Instrument Sans", size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

// MARK: - Interactive Button Components

struct InteractiveButton: View {
    let label: String
    let bgColor: Color
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Instrument Sans", size: 14))
                .fontWeight(.bold)
                .foregroundColor(bgColor.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(bgColor.opacity(isHovered ? 0.25 : 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(bgColor.opacity(isHovered ? 0.45 : 0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: bgColor.opacity(isHovered ? 0.15 : 0), radius: 12)
                .scaleEffect(isPressed ? 0.97 : isHovered ? 1.02 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
                .animation(.spring(response: 0.08, dampingFraction: 0.9), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct ActionButton: View {
    let label: String
    let subtitle: String?
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.custom("Instrument Sans", size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(isHovered ? 0.6 : 0.35))
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("Instrument Sans", size: 9))
                        .foregroundColor(.white.opacity(isHovered ? 0.35 : 0.2))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 9)
            .background(Color.white.opacity(isPressed ? 0.07 : isHovered ? 0.04 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.18 : 0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isPressed ? 0.95 : isHovered ? 1.03 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.08, dampingFraction: 0.9), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
