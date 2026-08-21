import Foundation

struct TaskItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var taskDescription: String
    var status: TaskStatus
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var syncStatus: SyncStatus
    var isArchived: Bool
    var subtasks: [SubtaskItem]
}
