import Foundation

protocol TaskRepositoryProtocol: AnyObject {
    func fetchTasks() throws -> [TaskItem]
    func observeTasks() -> AsyncStream<[TaskItem]>

    func createTask(title: String, description: String, subtasks: [SubtaskItem]) throws -> TaskItem
    func updateTask(id: UUID, title: String, description: String, subtasks: [SubtaskItem]?) throws
    func moveTask(id: UUID, to status: TaskStatus, at index: Int) throws
    func reorderTasks(in status: TaskStatus, orderedIDs: [UUID]) throws
    func deleteTask(id: UUID) throws
    func archiveTask(id: UUID) throws
    func unarchiveTask(id: UUID) throws

    func applyRemoteTask(_ dto: RemoteTaskDTO) throws
    func markSynced(taskId: UUID, remoteUpdatedAt: Date) throws
    func markFailed(taskId: UUID) throws

    func taskEntitySnapshot(for taskId: UUID) throws -> RemoteTaskDTO?
    func lastPullAt() throws -> Date?
    func setLastPullAt(_ date: Date) throws
    func pendingSyncCount() throws -> Int
    func failedSyncCount() throws -> Int
}

extension TaskRepositoryProtocol {
    func createTask(title: String, description: String) throws -> TaskItem {
        try createTask(title: title, description: description, subtasks: [])
    }

    func updateTask(id: UUID, title: String, description: String) throws {
        try updateTask(id: id, title: title, description: description, subtasks: nil)
    }
}
