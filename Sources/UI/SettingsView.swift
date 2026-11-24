import FossifyCommons
import SwiftUI

/// SettingsActivity.
struct SettingsView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @State private var dialog: SettingsDialog?

    enum SettingsDialog: String, Identifiable {
        case keyboardLanguage, manageLanguages, keyboardHeight, sound
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var config = config
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsItem("Keyboard language", value: KeyboardLanguage.title(config.keyboardLanguage)) {
                        dialog = .keyboardLanguage
                    }
                    SettingsItem("Manage keyboard languages") { dialog = .manageLanguages }

                    Text("Layout & appearance").sectionHeader(palette)
                    SettingsToggle("Show key borders", isOn: $config.showKeyBorders)
                    SettingsToggle("Show numbers on a separate row", isOn: $config.showNumbersRow)
                    SettingsToggle("Show emoji key", isOn: Binding(get: { config.showEmojiKey }, set: {
                        config.showEmojiKey = $0
                        if $0 { config.showLanguageSwitchKey = false }
                    }))
                    SettingsToggle("Show language switch key", isOn: Binding(get: { config.showLanguageSwitchKey }, set: {
                        config.showLanguageSwitchKey = $0
                        if $0 { config.showEmojiKey = false }
                    }))
                    SettingsItem("Keyboard height", value: "\(config.keyboardHeightPercentage)%") { dialog = .keyboardHeight }

                    Text("Keypress").sectionHeader(palette)
                    SettingsToggle("Show a popup on keypress", isOn: $config.showPopupOnKeypress)
                    SettingsToggle("Vibrate on keypress", isOn: $config.vibrateOnKeypress)
                    SettingsItem("Sound on keypress", value: config.soundOnKeypress.title) { dialog = .sound }

                    Text("Typing & input").sectionHeader(palette)
                    SettingsToggle("Start sentences with a capital letter", isOn: $config.enableSentencesCapitalization)

                    Text("Clipboard").sectionHeader(palette)
                    SettingsItem("Manage clipboard items") { router.push(.manageClipboardItems) }
                    SettingsToggle("Show clipboard content if available", isOn: $config.showClipboardContent)
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(item: $dialog) { dialog in
            switch dialog {
            case .keyboardLanguage:
                RadioDialog(title: nil, items: config.selectedLanguagesSorted.map { ($0, KeyboardLanguage.title($0)) },
                            selected: config.keyboardLanguage) { config.keyboardLanguage = $0 }
            case .manageLanguages:
                ManageKeyboardLanguagesDialog()
            case .keyboardHeight:
                RadioDialog(title: nil, items: keyboardHeightPercentages.map { ($0, "\($0)%") },
                            selected: config.keyboardHeightPercentage) { config.keyboardHeightPercentage = $0 }
            case .sound:
                RadioDialog(title: nil, items: SoundOnKeypress.allCases.map { ($0, $0.title) },
                            selected: config.soundOnKeypress) { config.soundOnKeypress = $0 }
            }
        }
    }
}

extension AppInfo {
    public static let keyboard = AppInfo(
        name: "Keyboard", icon: "keyboard", upstream: "Keyboard", port: "keyboard-ios", policy: "keyboard"
    )
}
