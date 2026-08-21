import Foundation
import Observation

@MainActor
@Observable
final class BoardViewModel {
    private(set) var allTasks: [TaskItem] = []
    private(set) var syncSnapshot = SyncSnapshot.initial

    var tasks: [TaskItem] {
        allTasks.filter { !$0.isArchived }
    }

    var archivedTasks: [TaskItem] {
        allTasks.filter(\.isArchived)
    }

    var tasksByStatus: [TaskStatus: [TaskItem]] {
        Dictionary(grouping: tasks, by: \.status)
    }

    private let repository: TaskRepositoryProtocol
    private let syncEngine: SyncEngine
    private let outbox: OutboxStoreProtocol
    private var tasksTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    init(
        repository: TaskRepositoryProtocol,
        syncEngine: SyncEngine,
        outbox: OutboxStoreProtocol
    ) {
        self.repository = repository
        self.syncEngine = syncEngine
        self.outbox = outbox
    }

    func start() {
        stop()

        tasksTask = Task {
            for await items in repository.observeTasks() {
                allTasks = items
            }
        }

        syncTask = Task {
            for await snapshot in await syncEngine.observeSyncState() {
                syncSnapshot = snapshot
            }
        }

        Task.detached(priority: .utility) { [syncEngine] in
            await syncEngine.syncNow(forceWhenOffline: false)
        }
    }

    func stop() {
        tasksTask?.cancel()
        syncTask?.cancel()
    }

    func createTask(title: String, description: String, subtasks: [SubtaskItem] = []) {
        try? repository.createTask(title: title, description: description, subtasks: subtasks)
    }

    func updateTask(id: UUID, title: String, description: String, subtasks: [SubtaskItem]) {
        try? repository.updateTask(id: id, title: title, description: description, subtasks: subtasks)
    }

    func deleteTask(id: UUID) {
        try? repository.deleteTask(id: id)
    }

    func archiveTask(id: UUID) {
        try? repository.archiveTask(id: id)
    }

    func unarchiveTask(id: UUID) {
        try? repository.unarchiveTask(id: id)
    }

    func moveTask(id: UUID, to status: TaskStatus, at index: Int) {
        try? repository.moveTask(id: id, to: status, at: index)
    }

    func reorderTasks(in status: TaskStatus, orderedIDs: [UUID]) {
        try? repository.reorderTasks(in: status, orderedIDs: orderedIDs)
    }

    func retrySync() {
        try? outbox.resetRetryState()
        Task.detached(priority: .utility) { [syncEngine] in
            await syncEngine.syncNow(forceWhenOffline: true)
        }
    }
}
