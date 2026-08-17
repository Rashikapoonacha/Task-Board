import Foundation

enum TaskStatus: String, CaseIterable, Codable, Sendable {
    case todo = "todo"
    case inProgress = "in_progress"
    case done = "done"

    var displayName: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}
