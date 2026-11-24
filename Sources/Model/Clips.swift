import Foundation
import Observation
import UIKit

/// The "clips" table (Clip entity + ClipsDao + ClipsHelper), stored as JSON in the keyboard's suite.
struct Clip: Codable, Hashable, Identifiable {
    var id: Int64
    var value: String
}

@Observable
final class ClipsStore {
    static let shared = ClipsStore()

    private(set) var clips: [Clip] = []
    @ObservationIgnored private let key = "keyboard_clips"

    private init() {
        reload()
    }

    /// Re-reads the table (the app and the extension share it).
    func reload() {
        let stored = Config.shared.d.data(forKey: key).flatMap { try? JSONDecoder().decode([Clip].self, from: $0) } ?? []
        clips = stored.sorted { $0.id < $1.id } // ORDER BY id
    }

    private func save() {
        Config.shared.d.set(try? JSONEncoder().encode(clips), forKey: key)
    }

    /// ClipsHelper.insertClip(): makes sure clips have unique values; returns the id or -1.
    @discardableResult
    func insertClip(_ value: String, id: Int64? = nil) -> Int64 {
        guard !clips.contains(where: { $0.value == value }) else { return -1 }
        if let id, let i = clips.firstIndex(where: { $0.id == id }) {
            clips[i].value = value // insertOrUpdate (REPLACE)
            save()
            return id
        }
        let newID = (clips.map(\.id).max() ?? 0) + 1
        clips.append(Clip(id: newID, value: value))
        save()
        return newID
    }

    func delete(_ ids: Set<Int64>) {
        clips.removeAll { ids.contains($0.id) }
        save()
    }

    /// After reordering: deleteAll() and re-insert in the new order.
    func replaceAll(with ordered: [Clip]) {
        clips = ordered.enumerated().map { Clip(id: Int64($0.offset + 1), value: $0.element.value) }
        save()
    }
}

/// Context.getCurrentClip().
func currentClip() -> String? {
    guard UIPasteboard.general.hasStrings else { return nil }
    return UIPasteboard.general.string
}
