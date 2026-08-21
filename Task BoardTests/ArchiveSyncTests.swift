import Foundation
import Testing
@testable import TaskBoard

struct ArchiveSyncTests {

    @Test func offlineArchiveSyncsWhenBackOnline() async throws {
        let remote = MockTaskRemoteService()
        var isOnline = false
        let device = try makeDevice(remote: remote, isOnline: { isOnline })

        let env = try await seedSyncedTask(on: device, remote: remote, title: "Offline archive")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)

        try env.repository.archiveTask(id: taskId)
        #expect(try active(env.repository).isEmpty)
        #expect(try archived(env.repository).count == 1)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .pending)

        await env.engine.syncNow(forceWhenOffline: false)
        #expect(remote.store[taskId]?.isArchived != true)
        #expect(try env.outbox.pendingCount() == 1)

        isOnline = true
        await env.engine.syncNow(forceWhenOffline: false)

        #expect(remote.store[taskId]?.isArchived == true)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .synced)
        #expect(try env.outbox.pendingCount() == 0)
        #expect(remote.updateCallCount >= 1)
    }

    @Test func offlineRestoreSyncsWhenBackOnline() async throws {
        let remote = MockTaskRemoteService()
        let device = try makeDevice(remote: remote)
        let env = try await seedSyncedTask(on: device, remote: remote, title: "Offline restore")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)

        try env.repository.archiveTask(id: taskId)
        await env.engine.syncNow(forceWhenOffline: true)
        #expect(remote.store[taskId]?.isArchived == true)

        try env.repository.unarchiveTask(id: taskId)
        #expect(try active(env.repository).count == 1)
        #expect(try archived(env.repository).isEmpty)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .pending)

        await env.engine.syncNow(forceWhenOffline: true)

        #expect(remote.store[taskId]?.isArchived == false)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .synced)
        #expect(try active(env.repository).count == 1)
    }

    @Test func deviceBPullsArchiveFromDeviceA() async throws {
        let remote = MockTaskRemoteService()
        let deviceA = try makeDevice(remote: remote)
        let envA = try await seedSyncedTask(on: deviceA, remote: remote, title: "Shared task")
        let taskId = try #require(try envA.repository.fetchTasks().first?.id)

        try envA.repository.archiveTask(id: taskId)
        await envA.engine.syncNow(forceWhenOffline: true)

        #expect(remote.store[taskId]?.isArchived == true)
        #expect(try active(envA.repository).isEmpty)

        let deviceB = try makeDevice(remote: remote)
        await deviceB.engine.syncNow(forceWhenOffline: true)

        let onB = try deviceB.repository.fetchTasks()
        #expect(onB.count == 1)
        #expect(onB.first?.isArchived == true)
        #expect(try active(deviceB.repository).isEmpty)
        #expect(try archived(deviceB.repository).count == 1)
    }

    @Test func deviceBPullsRestoreFromDeviceA() async throws {
        let remote = MockTaskRemoteService()
        let deviceA = try makeDevice(remote: remote)
        let envA = try await seedSyncedTask(on: deviceA, remote: remote, title: "Restore sync")
        let taskId = try #require(try envA.repository.fetchTasks().first?.id)

        try envA.repository.archiveTask(id: taskId)
        await envA.engine.syncNow(forceWhenOffline: true)

        let deviceB = try makeDevice(remote: remote)
        await deviceB.engine.syncNow(forceWhenOffline: true)
        #expect(try archived(deviceB.repository).count == 1)

        try envA.repository.unarchiveTask(id: taskId)
        await envA.engine.syncNow(forceWhenOffline: true)
        #expect(remote.store[taskId]?.isArchived == false)

        await deviceB.engine.syncNow(forceWhenOffline: true)

        #expect(try active(deviceB.repository).count == 1)
        #expect(try archived(deviceB.repository).isEmpty)
        #expect(try deviceB.repository.fetchTasks().first?.syncStatus == .synced)
    }

    @Test func restorePreservesWorkflowStatusAcrossDevices() async throws {
        let remote = MockTaskRemoteService()
        let deviceA = try makeDevice(remote: remote)
        let envA = try await seedSyncedTask(on: deviceA, remote: remote, title: "In progress")
        let taskId = try #require(try envA.repository.fetchTasks().first?.id)

        try envA.repository.moveTask(id: taskId, to: .inProgress, at: 0)
        await envA.engine.syncNow(forceWhenOffline: true)

        try envA.repository.archiveTask(id: taskId)
        await envA.engine.syncNow(forceWhenOffline: true)

        let deviceB = try makeDevice(remote: remote)
        await deviceB.engine.syncNow(forceWhenOffline: true)
        #expect(try deviceB.repository.fetchTasks().first?.status == .inProgress)
        #expect(try deviceB.repository.fetchTasks().first?.isArchived == true)

        try envA.repository.unarchiveTask(id: taskId)
        await envA.engine.syncNow(forceWhenOffline: true)

        await deviceB.engine.syncNow(forceWhenOffline: true)
        let restored = try #require(try deviceB.repository.fetchTasks().first)
        #expect(restored.status == .inProgress)
        #expect(restored.isArchived == false)
    }

    @Test func pendingOfflineArchiveNotOverwrittenByRemoteRestore() async throws {
        let remote = MockTaskRemoteService()
        let device = try makeDevice(remote: remote)
        let env = try await seedSyncedTask(on: device, remote: remote, title: "Pending archive")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)
        let base = try #require(try env.repository.localTaskState(for: taskId).3)

        try env.repository.archiveTask(id: taskId)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .pending)

        remote.store[taskId] = TestTaskFactory.remote(
            id: taskId,
            title: "Pending archive",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: base.addingTimeInterval(120),
            isArchived: false,
            baseRemoteUpdatedAt: base
        )

        await env.engine.syncNow(forceWhenOffline: true)

        #expect(try env.repository.fetchTasks().first?.isArchived == true)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .pending)
        #expect(try env.outbox.pendingCount() == 1)
    }

    @Test func newerRemoteRestoreWinsOverSyncedLocalArchive() async throws {
        let remote = MockTaskRemoteService()
        let device = try makeDevice(remote: remote)
        let env = try await seedSyncedTask(on: device, remote: remote, title: "Conflict restore")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)
        let base = try #require(try env.repository.localTaskState(for: taskId).3)

        try env.repository.archiveTask(id: taskId)
        await env.engine.syncNow(forceWhenOffline: true)
        #expect(try archived(env.repository).count == 1)

        remote.store[taskId] = TestTaskFactory.remote(
            id: taskId,
            title: "Conflict restore",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: base.addingTimeInterval(180),
            isArchived: false,
            baseRemoteUpdatedAt: base.addingTimeInterval(60)
        )

        await env.engine.syncNow(forceWhenOffline: true)

        #expect(try active(env.repository).count == 1)
        #expect(try archived(env.repository).isEmpty)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .synced)
        #expect(try env.outbox.pendingCount() == 0)
    }

    @Test func newerRemoteArchiveWinsOverSyncedLocalActiveTask() async throws {
        let remote = MockTaskRemoteService()
        let device = try makeDevice(remote: remote)
        let env = try await seedSyncedTask(on: device, remote: remote, title: "Remote archive")
        let taskId = try #require(try env.repository.fetchTasks().first?.id)
        let base = try #require(try env.repository.localTaskState(for: taskId).3)

        remote.store[taskId] = TestTaskFactory.remote(
            id: taskId,
            title: "Remote archive",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: base.addingTimeInterval(90),
            isArchived: true,
            baseRemoteUpdatedAt: base
        )

        await env.engine.syncNow(forceWhenOffline: true)

        #expect(try active(env.repository).isEmpty)
        #expect(try archived(env.repository).count == 1)
        #expect(try env.repository.fetchTasks().first?.syncStatus == .synced)
    }

    // MARK: - Helpers

    private typealias Device = (
        repository: TaskRepository,
        outbox: OutboxStore,
        engine: SyncEngine
    )

    private func makeDevice(
        remote: MockTaskRemoteService,
        isOnline: @escaping () -> Bool = { true }
    ) throws -> Device {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)
        let engine = SyncEngine(
            repository: repository,
            outbox: outbox,
            remote: remote,
            isOnline: isOnline
        )
        return (repository, outbox, engine)
    }

    private func seedSyncedTask(
        on device: Device,
        remote: MockTaskRemoteService,
        title: String
    ) async throws -> Device {
        _ = try device.repository.createTask(title: title, description: "")
        await device.engine.syncNow(forceWhenOffline: true)
        return device
    }

    private func active(_ repository: TaskRepository) throws -> [TaskItem] {
        try repository.fetchTasks().filter { !$0.isArchived }
    }

    private func archived(_ repository: TaskRepository) throws -> [TaskItem] {
        try repository.fetchTasks().filter(\.isArchived)
    }
}
