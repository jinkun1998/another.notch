import Foundation

struct QuickNote: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), text: String = "", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

final class QuickNoteStore: ObservableObject {
    static let shared = QuickNoteStore()

    @Published private(set) var notes: [QuickNote]

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "quickNotes") {
        self.defaults = defaults
        self.storageKey = storageKey
        notes = Self.load(from: defaults, key: storageKey)
    }

    @discardableResult
    func create() -> QuickNote {
        let note = QuickNote()
        notes.insert(note, at: 0)
        save()
        return note
    }

    func update(_ id: QuickNote.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].updatedAt = .now
        save()
    }

    func delete(_ id: QuickNote.ID) {
        notes.removeAll { $0.id == id }
        save()
    }

    private static func load(from defaults: UserDefaults, key: String) -> [QuickNote] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([QuickNote].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
