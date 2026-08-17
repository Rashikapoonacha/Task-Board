import Foundation
import Testing
@testable import TaskBoard

struct SyncEngineTests {

    @Test func pushThenPullMarksSynced() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        let engine = makeEngine(repository: repository, outbox: outbox, remote: remote)

        _ = try repository.createTask(title: "Sync", description: "Test")
        await engine.syncNow(forceWhenOffline: true)

        let tasks = try repository.fetchTasks()
        #expect(tasks.first?.syncStatus == .synced)
        #expect(try outbox.pendingCount() == 0)
        #expect(remote.createCallCount == 1)
        #expect(remote.fetchCallCount == 1)
    }

    @Test func pullSkipsPendingLocal() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        remote.failCreate = true
        let engine = makeEngine(repository: repository, outbox: outbox, remote: remote)

        let local = try repository.createTask(title: "Local", description: "Pending")
        let remoteTask = TestTaskFactory.remote(
            id: local.id,
            title: "Remote overwrite",
            description: "Should not apply",
            status: .done,
            createdAt: local.createdAt,
            updatedAt: Date().addingTimeInterval(3600)
        )
        remote.tasksToReturn = [remoteTask]

        await engine.syncNow(forceWhenOffline: true)

        let tasks = try repository.fetchTasks()
        #expect(tasks.first?.title == "Local")
        #expect(tasks.first?.syncStatus == .pending)
    }

    @Test func resetRetryStateAllowsImmediateRetry() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        remote.failCreate = true
        let engine = makeEngine(repository: repository, outbox: outbox, remote: remote)

        _ = try repository.createTask(title: "Retry", description: "Now")
        await engine.syncNow(forceWhenOffline: true)

        #expect(remote.createCallCount == 1)
        #expect(try outbox.fetchReady(now: Date()).isEmpty)

        remote.failCreate = false
        try outbox.resetRetryState()
        await engine.syncNow(forceWhenOffline: true)

        #expect(remote.createCallCount == 2)
        let tasks = try repository.fetchTasks()
        #expect(tasks.first?.syncStatus == .synced)
        #expect(try outbox.pendingCount() == 0)
    }

    @Test func incrementalPullDiscoversOfflineCreatedRemoteTask() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        let engine = makeEngine(repository: repository, outbox: outbox, remote: remote)

        await engine.syncNow(forceWhenOffline: true)
        #expect(try repository.lastPullAt() == nil)

        let createdAt = Date(timeIntervalSince1970: 100)
        let offlineCreated = TestTaskFactory.remote(
            id: UUID(),
            title: "Task X",
            updatedAt: createdAt
        )
        remote.store[offlineCreated.id] = offlineCreated

        await engine.syncNow(forceWhenOffline: true)

        let titles = try repository.fetchTasks().map(\.title)
        #expect(titles.contains("Task X"))
        #expect(try repository.lastPullAt() == createdAt)
    }

    @Test func lastPullAtUsesMaxRemoteUpdatedAtNotDeviceNow() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        let engine = makeEngine(repository: repository, outbox: outbox, remote: remote)

        let t0 = Date(timeIntervalSince1970: 1_000)
        remote.store[UUID()] = TestTaskFactory.remote(title: "Seed", updatedAt: t0)
        await engine.syncNow(forceWhenOffline: true)
        #expect(try repository.lastPullAt() == t0)

        let laterCreate = Date(timeIntervalSince1970: 1_100)
        let taskX = TestTaskFactory.remote(title: "From A", updatedAt: laterCreate)
        remote.store[taskX.id] = taskX
        await engine.syncNow(forceWhenOffline: true)

        #expect(try repository.lastPullAt() == laterCreate)
        #expect(remote.lastFetchUpdatedSince == t0)
        #expect(try repository.fetchTasks().map(\.title).contains("From A"))
    }

    @Test func newerRemoteEditWinsOverStaleOfflineEdit() async throws {
        let env = try await seededSyncedTask(title: "Original", description: "same")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)
        let base = try #require(try env.repository.localTaskState(for: taskId).3)

        try env.repository.updateTask(id: taskId, title: "Original", description: "A edited")

        let newer = TestTaskFactory.remote(
            id: taskId,
            title: "Original",
            description: "B edited",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: base.addingTimeInterval(60),
            baseRemoteUpdatedAt: base
        )
        env.remote.store[taskId] = newer

        await env.engine.syncNow(forceWhenOffline: true)

        let local = try #require(try env.repository.fetchTasks().first)
        #expect(local.taskDescription == "B edited")
        #expect(local.syncStatus == .synced)
        #expect(try env.outbox.pendingCount() == 0)
        #expect(env.remote.store[taskId]?.description == "B edited")
        #expect(env.remote.updateCallCount == 1)
    }

    @Test func remoteDeleteWinsOverStaleOfflineEdit() async throws {
        let env = try await seededSyncedTask(title: "Keep", description: "body")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)
        let base = try #require(try env.repository.localTaskState(for: taskId).3)

        try env.repository.updateTask(id: taskId, title: "Keep", description: "A edited")

        env.remote.store[taskId] = TestTaskFactory.remote(
            id: taskId,
            title: "Keep",
            description: "body",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: base.addingTimeInterval(30),
            isDeleted: true,
            baseRemoteUpdatedAt: base
        )

        await env.engine.syncNow(forceWhenOffline: true)

        #expect(try env.repository.fetchTasks().isEmpty)
        #expect(try env.outbox.pendingCount() == 0)
        #expect(env.remote.store[taskId]?.isDeleted == true)
        let state = try env.repository.localTaskState(for: taskId)
        #expect(state.1 == true)
        #expect(state.2 == .synced)
    }

    @Test func staleOfflineDeleteDoesNotOverwriteNewerRemoteEdit() async throws {
        let env = try await seededSyncedTask(title: "Live", description: "old")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)
        let base = try #require(try env.repository.localTaskState(for: taskId).3)

        try env.repository.deleteTask(id: taskId)

        env.remote.store[taskId] = TestTaskFactory.remote(
            id: taskId,
            title: "Live",
            description: "B edited",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: base.addingTimeInterval(45),
            baseRemoteUpdatedAt: base
        )

        await env.engine.syncNow(forceWhenOffline: true)

        let local = try #require(try env.repository.fetchTasks().first)
        #expect(local.taskDescription == "B edited")
        #expect(local.syncStatus == .synced)
        #expect(try env.outbox.pendingCount() == 0)
        #expect(env.remote.store[taskId]?.isDeleted != true)
        #expect(env.remote.store[taskId]?.description == "B edited")
    }

    @Test func legitimateOfflineCreateStillSyncs() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        let engine = makeEngine(repository: repository, outbox: outbox, remote: remote)

        let created = try repository.createTask(title: "Offline", description: "new")
        await engine.syncNow(forceWhenOffline: true)

        #expect(remote.store[created.id]?.title == "Offline")
        #expect(try repository.fetchTasks().first?.syncStatus == .synced)
        #expect(try outbox.pendingCount() == 0)
    }

    private func makeEngine(
        repository: TaskRepository,
        outbox: OutboxStore,
        remote: MockTaskRemoteService
    ) -> SyncEngine {
        SyncEngine(
            repository: repository,
            outbox: outbox,
            remote: remote,
            isOnline: { true }
        )
    }

    private func seededSyncedTask(title: String, description: String) async throws -> (
        repository: TaskRepository,
        outbox: OutboxStore,
        remote: MockTaskRemoteService,
        engine: SyncEngine
    ) {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let remote = MockTaskRemoteService()
        let engine = makeEngine(repository: repository, outbox: outbox, remote: remote)
        _ = try repository.createTask(title: title, description: description)
        await engine.syncNow(forceWhenOffline: true)
        return (repository, outbox, remote, engine)
    }
}
