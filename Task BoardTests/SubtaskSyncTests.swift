import Foundation
import Testing
@testable import TaskBoard

struct SubtaskSyncTests {

    @Test func pushIncludesSubtasksInRemoteStore() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        let engine = SyncEngine(
            repository: repository,
            outbox: outbox,
            remote: remote,
            isOnline: { true }
        )

        let subtasks = [SubtaskItem(id: UUID(), title: "Ship it", isComplete: false, sortOrder: 0)]
        let task = try repository.createTask(title: "Parent", description: "", subtasks: subtasks)
        await engine.syncNow(forceWhenOffline: true)

        #expect(remote.store[task.id]?.subtasks.count == 1)
        #expect(remote.store[task.id]?.subtasks.first?.title == "Ship it")
        #expect(try repository.fetchTasks().first?.syncStatus == .synced)
    }

    @Test func deviceBPullsSubtasksFromDeviceA() async throws {
        let remote = MockTaskRemoteService()
        let deviceA = try makeDevice(remote: remote)

        let subtasks = [
            SubtaskItem(id: UUID(), title: "One", isComplete: false, sortOrder: 0),
            SubtaskItem(id: UUID(), title: "Two", isComplete: true, sortOrder: 1)
        ]
        _ = try deviceA.repository.createTask(title: "Shared", description: "", subtasks: subtasks)
        await deviceA.engine.syncNow(forceWhenOffline: true)

        let deviceB = try makeDevice(remote: remote)
        await deviceB.engine.syncNow(forceWhenOffline: true)

        let fetched = try #require(try deviceB.repository.fetchTasks().first)
        #expect(fetched.subtasks.count == 2)
        #expect(fetched.subtasks[1].isComplete == true)
    }

    @Test func pendingLocalSubtasksNotOverwrittenByPull() async throws {
        let remote = MockTaskRemoteService()
        let device = try makeDevice(remote: remote)

        _ = try device.repository.createTask(title: "Parent", description: "", subtasks: [])
        await device.engine.syncNow(forceWhenOffline: true)
        let taskId = try #require(try device.repository.fetchTasks().first?.id)
        let base = try #require(try device.repository.localTaskState(for: taskId).3)

        let localSubtasks = [SubtaskItem(id: UUID(), title: "Local only", isComplete: false, sortOrder: 0)]
        try device.repository.updateTask(
            id: taskId,
            title: "Parent",
            description: "",
            subtasks: localSubtasks
        )

        remote.store[taskId] = TestTaskFactory.remote(
            id: taskId,
            title: "Parent",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: base.addingTimeInterval(120),
            subtasks: [],
            baseRemoteUpdatedAt: base
        )
        remote.failUpdate = true

        await device.engine.syncNow(forceWhenOffline: true)

        let fetched = try #require(try device.repository.fetchTasks().first)
        #expect(fetched.subtasks.count == 1)
        #expect(fetched.subtasks.first?.title == "Local only")
        #expect(fetched.syncStatus == .pending)
    }

    private typealias Device = (
        repository: TaskRepository,
        outbox: OutboxStore,
        engine: SyncEngine
    )

    private func makeDevice(remote: MockTaskRemoteService) throws -> Device {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let engine = SyncEngine(
            repository: repository,
            outbox: outbox,
            remote: remote,
            isOnline: { true }
        )
        return (repository, outbox, engine)
    }
}
