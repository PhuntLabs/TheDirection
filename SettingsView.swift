import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(settings.localized(.darkMode))) {
                    Toggle(isOn: $settings.isDarkMode) {
                        Text(settings.localized(.darkMode))
                    }
                }
                Section(header: Text(settings.localized(.language))) {
                    Picker(settings.localized(.language), selection: $settings.language) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                        Text("Français").tag("fr")
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("Reputation")) {
                    HStack { Text("Score"); Spacer(); Text("\(settings.reputationScore)").bold() }
                }
            }
            .navigationTitle(settings.localized(.settingsTab))
        }
    }
}

