import Foundation
import Testing
@testable import TaskBoard

final class MockTaskRemoteService: TaskRemoteServiceProtocol, @unchecked Sendable {
    var createCallCount = 0
    var updateCallCount = 0
    var deleteCallCount = 0
    var fetchCallCount = 0
    var lastFetchUpdatedSince: Date?
    var tasksToReturn: [RemoteTaskDTO] = []
    var store: [UUID: RemoteTaskDTO] = [:]
    var failCreate = false
    var failUpdate = false
    var failDelete = false

    func fetchTasks(updatedSince: Date?) async throws -> [RemoteTaskDTO] {
        fetchCallCount += 1
        lastFetchUpdatedSince = updatedSince
        var items = Array(store.values) + tasksToReturn
        var seen = Set<UUID>()
        items = items.filter { seen.insert($0.id).inserted }
        if let updatedSince {
            items = items.filter { $0.updatedAt > updatedSince }
        }
        return items
    }

    func createTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult {
        createCallCount += 1
        if failCreate {
            throw NSError(domain: "test", code: 1)
        }
        let result = RemoteConcurrency.create(existing: store[task.id], incoming: task)
        if case .success(let written) = result {
            store[written.id] = written
        }
        return result
    }

    func updateTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult {
        updateCallCount += 1
        if failUpdate {
            throw NSError(domain: "test", code: 1)
        }
        let result = RemoteConcurrency.update(existing: store[task.id], incoming: task)
        if case .success(let written) = result {
            store[written.id] = written
        }
        return result
    }

    func deleteTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult {
        deleteCallCount += 1
        if failDelete {
            throw NSError(domain: "test", code: 1)
        }
        let result = RemoteConcurrency.delete(existing: store[task.id], incoming: task)
        switch result {
        case .success(let written):
            store[written.id] = written
        case .conflict:
            break
        }
        return result
    }
}

enum TestTaskFactory {
    static func remote(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        status: TaskStatus = .todo,
        sortOrder: Int = 0,
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date,
        isDeleted: Bool = false,
        isArchived: Bool = false,
        subtasks: [SubtaskItem] = [],
        baseRemoteUpdatedAt: Date? = nil
    ) -> RemoteTaskDTO {
        RemoteTaskDTO(
            id: id,
            title: title,
            description: description,
            status: status,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted,
            isArchived: isArchived,
            subtasks: subtasks,
            baseRemoteUpdatedAt: baseRemoteUpdatedAt
        )
    }
}
