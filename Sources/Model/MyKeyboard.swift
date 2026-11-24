import Foundation
import UIKit

/// One `<Row>`/`<Key>` of the upstream XML layouts (see LayoutData.swift for the short keys).
struct KeyDef: Decodable {
    var c: Int?
    var l: String?
    var p: String?
    var k: String?
    var w: Double?
    var g: Double?
    var e: Int?
    var i: String?
    var s: String?
    var n: String?
    var r: Bool?
    var o: String?
}

struct RowDef: Decodable {
    var numbers: Bool?
    var w: Double?
    var keys: [KeyDef]
}

enum Layouts {
    static let all: [String: [RowDef]] =
        (try? JSONDecoder().decode([String: [RowDef]].self, from: Data(layoutsJSON.utf8))) ?? [:]
}

/// Icons drawn on keys (the upstream vector drawables, as SF Symbols).
enum KeyIcon: String {
    case shift, delete, emoji, enter, settings, language, search, next, send

    func symbol(shift state: ShiftState = .off) -> String {
        switch self {
        case .shift:
            switch state {
            case .off: return "shift"
            case .onOneChar: return "shift.fill"
            case .onPermanent: return "capslock.fill"
            }
        case .delete: return "delete.left"
        case .emoji: return "face.smiling"
        case .enter: return "arrow.turn.down.left"
        case .settings: return "gearshape"
        case .language: return "globe"
        case .search: return "magnifyingglass"
        case .next: return "arrow.right"
        case .send: return "paperplane"
        }
    }
}

/// What the Enter key does / shows (EditorInfo.IME_ACTION_*).
enum EnterKeyType {
    case none, search, next, send

    init(_ returnKey: UIReturnKeyType?) {
        switch returnKey {
        case .search?, .google?, .yahoo?: self = .search
        case .next?, .go?, .route?, .continue?: self = .next
        case .send?: self = .send
        default: self = .none
        }
    }
}

/// Port of MyKeyboard: the keys of one layout, positioned for the available width.
final class MyKeyboard {
    /// R.dimen.key_height.
    static let keyHeight: CGFloat = 60

    final class Key {
        var code = 0
        var label = ""
        var topSmallNumber = ""
        var icon: KeyIcon?
        var secondaryIcon: KeyIcon?
        var width: CGFloat
        var height: CGFloat
        var gap: CGFloat
        var x: CGFloat = 0
        var y: CGFloat = 0
        var pressed = false
        var focused = false
        var popupCharacters: String?
        var role: String?
        var edgeFlags = 0
        /// The popup keyboard layout: "template" (built from popupCharacters) or a layout name.
        var popupLayout: String?
        var repeatable = false

        init(width: CGFloat, height: CGFloat, gap: CGFloat) {
            self.width = width
            self.height = height
            self.gap = gap
        }

        /// isInside(): keys anchored to an edge also take the touches between them and the edge.
        func isInside(_ px: CGFloat, _ py: CGFloat) -> Bool {
            let leftEdge = edgeFlags & 1 > 0, rightEdge = edgeFlags & 2 > 0
            return (px >= x || leftEdge && px <= x + width) && (px < x + width || rightEdge && px >= x)
                && py >= y && py < y + height
        }

        /// getContentDescription().
        func accessibilityLabel(showEmojiKey: Bool) -> String {
            switch code {
            case KeyCode.shift: return "Shift"
            case KeyCode.modeChange, KeyCode.symbolsModeChange: return "Change keyboard type"
            case KeyCode.enter: return "Enter"
            case KeyCode.delete: return "Delete"
            case KeyCode.space: return "Spacebar"
            case KeyCode.emojiOrLanguage: return showEmojiKey ? "Emojis" : "Keyboard language"
            case KeyCode.popupEmoji: return "Emojis"
            case KeyCode.popupSettings: return "Settings"
            default: return label
            }
        }
    }

    var shiftState = ShiftState.off
    var height: CGFloat = 0
    var minWidth: CGFloat = 0
    var keys: [Key] = []

    private let displayWidth: CGFloat
    private let heightMultiplier: CGFloat

    /// MyKeyboard(context, xmlLayoutResId, enterKeyType).
    init(layout: String, enterKeyType: EnterKeyType, width: CGFloat, config: Config) {
        displayWidth = width
        heightMultiplier = CGFloat(config.keyboardHeightPercentage) / 100
        let defaultWidth = width / 10
        let showNumbersRow = config.showNumbersRow
        var y: CGFloat = 0
        for row in Layouts.all[layout] ?? [] {
            if row.numbers == true && !showNumbersRow { continue }
            let rowWidth = row.w.map { CGFloat($0) / 100 * width } ?? defaultWidth
            let rowHeight = (MyKeyboard.keyHeight * heightMultiplier).rounded()
            var x: CGFloat = 0
            for def in row.keys {
                let key = Key(width: def.w.map { CGFloat($0) / 100 * width } ?? rowWidth, height: rowHeight,
                              gap: def.g.map { CGFloat($0) / 100 * width } ?? 0)
                key.x = x + key.gap
                key.y = y
                key.label = def.l ?? ""
                key.code = def.c ?? 0
                if !key.label.isEmpty && key.code == 0 {
                    key.code = Int(key.label.utf16.first ?? 0)
                }
                key.popupCharacters = def.p
                key.popupLayout = def.k
                key.repeatable = def.r ?? false
                key.edgeFlags = def.e ?? 0
                key.icon = def.i.flatMap(KeyIcon.init)
                key.secondaryIcon = def.s.flatMap(KeyIcon.init)
                key.topSmallNumber = def.n ?? ""
                key.role = def.o
                if showNumbersRow {
                    // Removes numbers (i.e 0-9) from the popupCharacters if numbers row is enabled
                    let had = key.popupCharacters != nil
                    key.popupCharacters = key.popupCharacters?.replacingOccurrences(of: "[0-9]+", with: "", options: .regularExpression)
                    if had && (key.popupCharacters ?? "").isEmpty {
                        key.popupCharacters = nil
                        key.popupLayout = nil
                    }
                }
                if key.code == KeyCode.enter {
                    switch enterKeyType {
                    case .search: key.icon = .search
                    case .next: key.icon = .next
                    case .send: key.icon = .send
                    case .none: key.icon = .enter
                    }
                }
                keys.append(key)
                x += key.gap + key.width
                minWidth = max(minWidth, x)
            }
            y += rowHeight
        }
        height = y
    }

    /// MyKeyboard(context, layoutTemplateResId, characters, keyWidth): the popup of a long pressed key,
    /// at most `maxKeysPerMiniRow` keys per row.
    init(characters: String, keyWidth: CGFloat, config: Config) {
        displayWidth = keyWidth
        heightMultiplier = CGFloat(config.keyboardHeightPercentage) / 100
        let rowHeight = MyKeyboard.keyHeight
        var x: CGFloat = 0, y: CGFloat = 0, column = 0
        for character in characters {
            if column >= maxKeysPerMiniRow {
                column = 0
                x = 0
                y += rowHeight
            }
            let key = Key(width: keyWidth, height: rowHeight, gap: 0)
            key.x = x
            key.y = y
            key.label = String(character)
            key.code = Int(String(character).utf16.first ?? 0)
            column += 1
            x += key.width + key.gap
            keys.append(key)
            minWidth = max(minWidth, x)
        }
        height = y + rowHeight
    }

    @discardableResult
    func setShifted(_ state: ShiftState) -> Bool {
        guard shiftState != state else { return false }
        shiftState = state
        return true
    }
}
