import SwiftUI

struct SettingsView: View {
    let settings: SettingsManager
    let soundPlayer: SoundPlayer

    @State private var selectedLeadTime: Int
    @State private var selectedSound: AlertSound
    @State private var launchOnLogin: Bool

    init(settings: SettingsManager, soundPlayer: SoundPlayer) {
        self.settings = settings
        self.soundPlayer = soundPlayer
        _selectedLeadTime = State(initialValue: settings.leadTimeSeconds)
        _selectedSound = State(initialValue: settings.alertSound)
        _launchOnLogin = State(initialValue: settings.launchOnLogin)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsSection("ALERT BEFORE EVENT") {
                HStack(spacing: 2) {
                    SegmentButton(label: "At time", value: 0, selected: $selectedLeadTime) {
                        settings.leadTimeSeconds = 0
                    }
                    SegmentButton(label: "15s", value: 15, selected: $selectedLeadTime) {
                        settings.leadTimeSeconds = 15
                    }
                    SegmentButton(label: "30s", value: 30, selected: $selectedLeadTime) {
                        settings.leadTimeSeconds = 30
                    }
                    SegmentButton(label: "1 min", value: 60, selected: $selectedLeadTime) {
                        settings.leadTimeSeconds = 60
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            settingsDivider

            settingsSection("ALERT SOUND") {
                VStack(spacing: 4) {
                    ForEach(AlertSound.allCases, id: \.self) { sound in
                        SoundRow(
                            sound: sound,
                            isSelected: selectedSound == sound,
                            onSelect: {
                                selectedSound = sound
                                settings.alertSound = sound
                            },
                            onPreview: {
                                soundPlayer.play(sound)
                            }
                        )
                    }
                }
            }

            settingsDivider

            settingsSection("GENERAL") {
                HStack {
                    Text("Open on login")
                        .font(.custom("Instrument Sans", size: 13))
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Toggle("", isOn: $launchOnLogin)
                        .toggleStyle(.switch)
                        .tint(Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.5))
                        .onChange(of: launchOnLogin) { _, newValue in
                            settings.launchOnLogin = newValue
                        }
                }
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 28/255, green: 28/255, blue: 40/255).opacity(0.98),
                    Color(red: 22/255, green: 22/255, blue: 32/255).opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Instrument Sans", size: 10))
                .fontWeight(.bold)
                .tracking(3)
                .foregroundColor(.white.opacity(0.25))
            content()
        }
        .padding(.vertical, 12)
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
    }
}

// MARK: - Segment Button

struct SegmentButton: View {
    let label: String
    let value: Int
    @Binding var selected: Int
    let onSelect: () -> Void

    @State private var isPressed = false

    private var isActive: Bool { selected == value }

    var body: some View {
        Button(action: {
            selected = value
            onSelect()
        }) {
            Text(label)
                .font(.custom("Instrument Sans", size: 12))
                .fontWeight(.semibold)
                .foregroundColor(isActive ? Color(red: 147/255, green: 197/255, blue: 253/255).opacity(0.95) : .white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isActive ? Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.2) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.25) : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(isPressed ? 0.96 : 1)
                .animation(.spring(response: 0.08, dampingFraction: 0.9), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Sound Row

struct SoundRow: View {
    let sound: AlertSound
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .stroke(isSelected ? Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.6) : Color.white.opacity(0.15), lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color(red: 99/255, green: 160/255, blue: 246/255).opacity(0.9) : Color.clear)
                            .frame(width: 8, height: 8)
                    )

                Text(sound.displayName)
                    .font(.custom("Instrument Sans", size: 13))
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(isSelected ? 0.8 : 0.5))

                Spacer()

                Button(action: onPreview) {
                    Text("Preview")
                        .font(.custom("Instrument Sans", size: 11))
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.08) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.15) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
