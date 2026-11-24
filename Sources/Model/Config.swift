import FossifyCommons
import Foundation
import Observation

/// Port of the keyboard Config (SharedPreferences -> UserDefaults); colors live in FossifyCommons.BaseConfig.
/// Uses the app group suite shared with the keyboard extension, which also keeps the generic keys
/// (vibrate_on_keypress, ...) apart from other apps inside the launcher.
@Observable
final class Config {
    static let shared = Config()

    /// App group of the app and its keyboard extension, as entitled after re-signing (Jimpactor
    /// registers `group.org.fossify.keyboard.ios.<TEAMID>`, see FossifyCommons.AppGroup). Without
    /// the entitlement this is simply a separate preferences domain.
    nonisolated static let suiteName = AppGroup.resolve("group.org.fossify.keyboard.ios") ?? "group.org.fossify.keyboard.ios"

    @ObservationIgnored let d = UserDefaults(suiteName: Config.suiteName) ?? .standard

    var vibrateOnKeypress = true { didSet { d.set(vibrateOnKeypress, forKey: "vibrate_on_keypress") } }
    var soundOnKeypress = SoundOnKeypress.system { didSet { d.set(soundOnKeypress.rawValue, forKey: "sound_on_keypress") } }
    var showPopupOnKeypress = true { didSet { d.set(showPopupOnKeypress, forKey: "show_popup_on_keypress") } }
    var enableSentencesCapitalization = true { didSet { d.set(enableSentencesCapitalization, forKey: "sentences_capitalization") } }
    var showEmojiKey = true { didSet { d.set(showEmojiKey, forKey: "show_emoji_key") } }
    var showLanguageSwitchKey = false { didSet { d.set(showLanguageSwitchKey, forKey: "show_language_switch_key") } }
    var showKeyBorders = true { didSet { d.set(showKeyBorders, forKey: "show_key_borders") } }
    var keyboardLanguage = 0 { didSet { d.set(keyboardLanguage, forKey: "keyboard_language") } }
    var keyboardHeightPercentage = 100 { didSet { d.set(keyboardHeightPercentage, forKey: "height_percentage") } }
    var showClipboardContent = true { didSet { d.set(showClipboardContent, forKey: "show_clipboard_content") } }
    var showNumbersRow = false { didSet { d.set(showNumbersRow, forKey: "show_numbers_row") } }
    var selectedLanguages: Set<Int> = [] {
        didSet { d.set(selectedLanguages.sorted().map(String.init), forKey: "selected_languages") }
    }
    var recentlyUsedEmojis: [String] = [] {
        didSet { d.set(recentlyUsedEmojis.joined(separator: "|"), forKey: "recently_used_emojis") }
    }

    private init() {
        reload()
    }

    /// Re-reads everything, e.g. when the keyboard extension appears after the app changed settings.
    func reload() {
        func bool(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) as? Bool ?? def }
        let defaultLanguage = Config.defaultLanguage
        vibrateOnKeypress = bool("vibrate_on_keypress", true)
        soundOnKeypress = SoundOnKeypress(rawValue: d.object(forKey: "sound_on_keypress") as? Int ?? 1) ?? .system
        showPopupOnKeypress = bool("show_popup_on_keypress", true)
        enableSentencesCapitalization = bool("sentences_capitalization", true)
        showEmojiKey = bool("show_emoji_key", true)
        showLanguageSwitchKey = bool("show_language_switch_key", false)
        showKeyBorders = bool("show_key_borders", true)
        keyboardLanguage = d.object(forKey: "keyboard_language") as? Int ?? defaultLanguage
        keyboardHeightPercentage = d.object(forKey: "height_percentage") as? Int ?? 100
        showClipboardContent = bool("show_clipboard_content", true)
        showNumbersRow = bool("show_numbers_row", false)
        let stored = (d.stringArray(forKey: "selected_languages") ?? [String(defaultLanguage)]).compactMap { Int($0) }
        selectedLanguages = Set(stored)
        recentlyUsedEmojis = (d.string(forKey: "recently_used_emojis") ?? "\u{1F430}").split(separator: "|").map(String.init)
    }

    /// getDefaultLanguage(): Russian for Russian locales, English (QWERTY) otherwise.
    static var defaultLanguage: Int {
        Locale.current.identifier.lowercased().hasPrefix("ru_") ? KeyboardLanguage.russian : KeyboardLanguage.englishQwerty
    }

    func addRecentEmoji(_ emoji: String) {
        var recent = recentlyUsedEmojis
        recent.removeAll { $0 == emoji }
        recent.insert(emoji, at: 0)
        recentlyUsedEmojis = Array(recent.prefix(recentEmojisLimit))
    }

    /// getSelectedLanguagesSorted().
    var selectedLanguagesSorted: [Int] {
        selectedLanguages.sorted { KeyboardLanguage.title($0) < KeyboardLanguage.title($1) }
    }

    // MARK: colors shared with the keyboard extension

    /// The app writes its BaseConfig colors into the app group, so the extension can draw with them.
    func exportColors() {
        let c = BaseConfig.shared
        d.set(c.theme.rawValue, forKey: "theme")
        d.set(Int(c.customTextColor), forKey: "text_color")
        d.set(Int(c.customBackgroundColor), forKey: "background_color")
        d.set(Int(c.customPrimaryColor), forKey: "primary_color")
    }

    /// In the extension: copy the app's colors into this process' BaseConfig.
    func importColors() {
        guard d.object(forKey: "theme") != nil else { return }
        let c = BaseConfig.shared
        if let t = ThemeKind(rawValue: d.integer(forKey: "theme")), c.theme != t { c.theme = t }
        for (key, path) in [("text_color", \BaseConfig.customTextColor), ("background_color", \.customBackgroundColor),
                            ("primary_color", \.customPrimaryColor)] {
            if let v = d.object(forKey: key) as? Int, c[keyPath: path] != UInt32(truncatingIfNeeded: v) {
                c[keyPath: path] = UInt32(truncatingIfNeeded: v)
            }
        }
    }
}
