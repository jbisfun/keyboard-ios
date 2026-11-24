import Foundation

enum ShiftState: Int, Comparable {
    case off = 0, onOneChar, onPermanent

    static func < (a: ShiftState, b: ShiftState) -> Bool { a.rawValue < b.rawValue }
}

/// Limit the count of alternative characters that show up at long pressing a key.
let maxKeysPerMiniRow = 9

enum SoundOnKeypress: Int, CaseIterable {
    case none = 0, system, always

    var title: String {
        switch self {
        case .none: return "Off"
        case .system: return "Follow system"
        case .always: return "Always on"
        }
    }
}

/// MyKeyboard.KEYCODE_*.
enum KeyCode {
    static let shift = -1
    static let modeChange = -2
    static let symbolsModeChange = -3
    static let enter = -4
    static let delete = -5
    static let space = 32
    static let emojiOrLanguage = -6
    static let popupEmoji = -7
    static let popupSettings = -8
}

let keyRoleTools = "tools"

/// SimpleKeyboardIME.KEYBOARD_*.
enum KeyboardMode {
    case letters, symbols, symbolsShift, numbers, phone, symbolsAlt
}

let keyboardHeightPercentages = [70, 80, 90, 100, 120, 140, 160]
let recentEmojisLimit = 36

/// LANGUAGE_* (stored ids are the upstream ones).
enum KeyboardLanguage {
    static let englishQwerty = 0
    static let russian = 1
    static let frenchAzerty = 2
    static let englishQwertz = 3
    static let spanish = 4
    static let german = 5
    static let englishDvorak = 6
    static let romanian = 7
    static let slovenian = 8
    static let bulgarian = 9
    static let turkishQ = 10
    static let lithuanian = 11
    static let bengali = 12
    static let greek = 13
    static let norwegian = 14
    static let swedish = 15
    static let danish = 16
    static let frenchBepo = 17
    static let vietnameseTelex = 18
    static let polish = 19
    static let ukrainian = 20
    static let chuvash = 22
    static let esperanto = 23
    static let hebrew = 24
    static let arabic = 25
    static let centralKurdish = 26
    static let belarusianCyrl = 27
    static let belarusianLatn = 28
    static let kabyleAzerty = 29
    static let czechQwerty = 30
    static let italian = 31
    static let czechQwertz = 32
    static let germanQwertz = 33
    static let portuguese = 34
    static let portugueseHcesar = 35
    static let dutch = 36
    static let latvian = 37
    static let turkish = 38
    static let englishAsset = 39
    static let englishColemak = 40
    static let englishColemakDH = 41
    static let englishNiro = 42
    static let englishSoul = 43
    static let englishWorkman = 44

    /// SUPPORTED_LANGUAGES.
    static let supported = [
        arabic, belarusianCyrl, belarusianLatn, bengali, bulgarian, centralKurdish, chuvash, czechQwerty, czechQwertz,
        danish, dutch, englishQwerty, englishQwertz, englishAsset, englishColemak, englishColemakDH, englishDvorak,
        englishNiro, englishSoul, englishWorkman, esperanto, frenchAzerty, frenchBepo, german, germanQwertz, greek,
        hebrew, italian, kabyleAzerty, latvian, lithuanian, norwegian, polish, portuguese, portugueseHcesar, romanian,
        russian, slovenian, spanish, swedish, turkish, turkishQ, ukrainian, vietnameseTelex,
    ]

    /// getKeyboardLanguageText().
    static func title(_ language: Int) -> String {
        switch language {
        case arabic: return "Arabic"
        case belarusianCyrl: return "Belarusan (Cyrillic)"
        case belarusianLatn: return "Belarusan (Latin)"
        case bengali: return "Bengali"
        case bulgarian: return "Bulgarian"
        case centralKurdish: return "Central Kurdish"
        case chuvash: return "Chuvash"
        case czechQwerty: return "Czech (QWERTY)"
        case czechQwertz: return "Czech (QWERTZ)"
        case danish: return "Danish"
        case dutch: return "Dutch"
        case englishAsset: return "English (Asset)"
        case englishColemak: return "English (Colemak)"
        case englishColemakDH: return "English (Colemak-DH)"
        case englishDvorak: return "English (DVORAK)"
        case englishNiro: return "English (Niro)"
        case englishQwertz: return "English (QWERTZ)"
        case englishSoul: return "English (Soul)"
        case englishWorkman: return "English (Workman)"
        case esperanto: return "Esperanto"
        case frenchAzerty: return "French (AZERTY)"
        case frenchBepo: return "French (BEPO)"
        case german: return "German"
        case germanQwertz: return "German (QWERTZ)"
        case greek: return "Greek"
        case hebrew: return "Hebrew"
        case italian: return "Italian"
        case kabyleAzerty: return "Kabyle (AZERTY)"
        case latvian: return "Latvian"
        case lithuanian: return "Lithuanian"
        case norwegian: return "Norwegian"
        case polish: return "Polish"
        case portuguese: return "Portuguese"
        case portugueseHcesar: return "Portuguese (HCESAR)"
        case romanian: return "Romanian"
        case russian: return "Russian"
        case slovenian: return "Slovenian"
        case spanish: return "Spanish"
        case swedish: return "Swedish"
        case turkish: return "Turkish"
        case turkishQ: return "Turkish (Q)"
        case ukrainian: return "Ukrainian"
        case vietnameseTelex: return "Vietnamese (Telex)"
        default: return "English (QWERTY)"
        }
    }

    /// getKeyboardLayoutXML().
    static func layout(_ language: Int) -> String {
        switch language {
        case arabic: return "keys_letters_arabic"
        case belarusianCyrl: return "keys_letters_belarusian_cyrl"
        case belarusianLatn: return "keys_letters_belarusian_latn"
        case bengali: return "keys_letters_bengali"
        case bulgarian: return "keys_letters_bulgarian"
        case centralKurdish: return "keys_letters_central_kurdish"
        case chuvash: return "keys_letters_chuvash"
        case czechQwerty: return "keys_letters_czech_qwerty"
        case czechQwertz: return "keys_letters_czech_qwertz"
        case danish: return "keys_letters_danish"
        case dutch: return "keys_letters_dutch"
        case englishAsset: return "keys_letters_english_asset"
        case englishColemak: return "keys_letters_english_colemak"
        case englishColemakDH: return "keys_letters_english_colemakdh"
        case englishDvorak: return "keys_letters_english_dvorak"
        case englishNiro: return "keys_letters_english_niro"
        case englishQwertz: return "keys_letters_english_qwertz"
        case englishSoul: return "keys_letters_english_soul"
        case englishWorkman: return "keys_letters_english_workman"
        case esperanto: return "keys_letters_esperanto"
        case frenchAzerty: return "keys_letters_french_azerty"
        case frenchBepo: return "keys_letters_french_bepo"
        case german: return "keys_letters_german"
        case germanQwertz: return "keys_letters_german_qwertz"
        case greek: return "keys_letters_greek"
        case hebrew: return "keys_letters_hebrew"
        case italian: return "keys_letters_italian"
        case kabyleAzerty: return "keys_letters_kabyle_azerty"
        case latvian: return "keys_letters_latvian"
        case lithuanian: return "keys_letters_lithuanian"
        case norwegian: return "keys_letters_norwegian"
        case polish: return "keys_letters_polish"
        case portuguese: return "keys_letters_portuguese"
        case portugueseHcesar: return "keys_letters_portuguese_hcesar"
        case romanian: return "keys_letters_romanian"
        case russian: return "keys_letters_russian"
        case slovenian: return "keys_letters_slovenian"
        case swedish: return "keys_letters_swedish"
        case spanish: return "keys_letters_spanish_qwerty"
        case turkish: return "keys_letters_turkish"
        case turkishQ: return "keys_letters_turkish_q"
        case ukrainian: return "keys_letters_ukrainian"
        default: return "keys_letters_english_qwerty"
        }
    }
}
