import CoreText
import Foundation
import UIKit

/// EmojiHelper: one emoji of emoji_spec.txt with its skin tone variants.
struct EmojiData: Hashable {
    var category: String
    var emoji: String
    var variants: [String]
}

enum Emojis {
    static let recentlyUsed = "recently_used_emojis"

    /// parseRawEmojiSpecsFile(), cached.
    static let all: [EmojiData] = {
        var emojis: [EmojiData] = []
        var editor: [String]?
        var category: String?
        func commit() {
            if let list = editor, let base = list.first {
                // add only the base emoji for now, ignore the variations
                emojis.append(EmojiData(category: category ?? "none", emoji: base, variants: Array(list.dropFirst())))
            }
            editor = nil
        }
        for line in emojiSpec.components(separatedBy: "\n") {
            if line.hasPrefix("#") {
                continue
            } else if line.hasPrefix("[") {
                commit()
                category = line.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            } else {
                if !line.hasPrefix("\t") { commit() }
                let data = line.components(separatedBy: ";")
                if data.count == 3 {
                    let emoji = data[0].trimmingCharacters(in: .whitespaces)
                    if editor != nil { editor!.append(emoji) } else { editor = [emoji] }
                }
            }
        }
        commit()
        return emojis
    }()

    /// The emojis the system font can draw as one glyph (Paint.hasGlyph()).
    static let supported: [EmojiData] = {
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 30, nil)
        return all.filter { data in
            let attributed = NSAttributedString(string: data.emoji, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attributed)
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            let glyphs = runs.reduce(0) { $0 + CTRunGetGlyphCount($1) }
            return glyphs == 1
        }
    }()

    static let categoryOrder = ["smileys_emotion", "people_body", "animals_nature", "food_drink", "travel_places",
                                "activities", "objects", "symbols", "flags"]

    /// getCategoryIconRes().
    static func icon(_ category: String) -> String {
        switch category {
        case "smileys_emotion": return "face.smiling"
        case "people_body": return "person"
        case "animals_nature": return "pawprint"
        case "food_drink": return "fork.knife"
        case "travel_places": return "car"
        case "activities": return "soccerball"
        case "objects": return "lightbulb"
        case "symbols": return "heart"
        case "flags": return "flag"
        default: return "clock.fill"
        }
    }

    /// getCategoryTitleRes().
    static func title(_ category: String) -> String {
        switch category {
        case "smileys_emotion": return "Smileys and emotions"
        case "people_body": return "People and body"
        case "animals_nature": return "Animals and nature"
        case "food_drink": return "Food and drink"
        case "travel_places": return "Travel and places"
        case "activities": return "Activities"
        case "objects": return "Objects"
        case "symbols": return "Symbols"
        case "flags": return "Flags"
        default: return "Recently used"
        }
    }

    /// prepareEmojiCategories(): recently used first, then the spec's categories in order.
    static func categories(recent: [String]) -> [(String, [EmojiData])] {
        let emojis = supported
        let recentData = recent.compactMap { e in emojis.first { $0.emoji == e }.map { EmojiData(category: recentlyUsed, emoji: $0.emoji, variants: $0.variants) } }
        var result: [(String, [EmojiData])] = []
        for data in recentData + emojis {
            if let i = result.firstIndex(where: { $0.0 == data.category }) {
                result[i].1.append(data)
            } else {
                result.append((data.category, [data]))
            }
        }
        return result
    }
}

/// parseRawJsonSpecsFile(): the Vietnamese Telex composition rules.
enum VietnameseTelex {
    static let rules: [String: String] =
        (try? JSONDecoder().decode([String: String].self, from: Data(vietnameseTelexJSON.utf8))) ?? [:]
}
