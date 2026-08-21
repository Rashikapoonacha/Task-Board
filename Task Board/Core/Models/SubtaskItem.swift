import Foundation

struct SubtaskItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var isComplete: Bool
    var sortOrder: Int
}

enum SubtaskStorage {
    static func decode(from data: Data?) -> [SubtaskItem] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([SubtaskItem].self, from: data)) ?? []
    }

    static func encode(_ subtasks: [SubtaskItem]) -> Data? {
        guard !subtasks.isEmpty else { return nil }
        return try? JSONEncoder().encode(subtasks)
    }
}
