import SwiftUI

struct SettingsView: View {
    let settings: SettingsManager
    @State private var selectedLeadTime: Int

    init(settings: SettingsManager) {
        self.settings = settings
        _selectedLeadTime = State(initialValue: settings.leadTimeSeconds)
    }

    var body: some View {
        Form {
            Picker("Alert before event:", selection: $selectedLeadTime) {
                Text("At event time").tag(0)
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: selectedLeadTime) { _, newValue in
                settings.leadTimeSeconds = newValue
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}
