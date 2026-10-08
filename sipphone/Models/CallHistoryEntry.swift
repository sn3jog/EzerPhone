import Foundation
import Combine
import SwiftUI

struct CallHistoryEntry: Identifiable, Codable, Equatable {
    enum Direction: String, Codable {
        case outgoing, incoming, missed
    }

    let id: UUID
    let remote: String
    let direction: Direction
    let date: Date
    let durationSeconds: Int

    init(id: UUID = UUID(), remote: String, direction: Direction, date: Date = Date(), durationSeconds: Int = 0) {
        self.id = id
        self.remote = remote
        self.direction = direction
        self.date = date
        self.durationSeconds = durationSeconds
    }
}

final class CallHistoryStore: ObservableObject {
    static let shared = CallHistoryStore()
    @Published private(set) var entries: [CallHistoryEntry] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("call_history.json")
    }()

    private init() {
        load()
    }

    func add(_ entry: CallHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func remove(_ entry: CallHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([CallHistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
