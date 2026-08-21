import Foundation
import Testing
@testable import TaskBoard

struct ConflictResolverTests {

    @Test func pendingLocalKeepsLocal() {
        let local = makeTask(syncStatus: .pending)
        let remote = makeRemote()
        let result = ConflictResolver.resolve(
            local: local,
            localIsDeleted: false,
            localSyncStatus: .pending,
            localRemoteUpdatedAt: nil,
            hasPendingOutbox: false,
            remote: remote
        )
        #expect(result == .keepLocal)
    }

    @Test func failedLocalKeepsLocal() {
        let local = makeTask(syncStatus: .failed)
        let remote = makeRemote()
        let result = ConflictResolver.resolve(
            local: local,
            localIsDeleted: false,
            localSyncStatus: .failed,
            localRemoteUpdatedAt: nil,
            hasPendingOutbox: false,
            remote: remote
        )
        #expect(result == .keepLocal)
    }

    @Test func pendingOutboxKeepsLocal() {
        let local = makeTask(syncStatus: .synced)
        let remote = makeRemote(updatedAt: Date().addingTimeInterval(100))
        let result = ConflictResolver.resolve(
            local: local,
            localIsDeleted: false,
            localSyncStatus: .synced,
            localRemoteUpdatedAt: local.updatedAt,
            hasPendingOutbox: true,
            remote: remote
        )
        #expect(result == .keepLocal)
    }

    @Test func syncedRemoteNewerAppliesRemote() {
        let local = makeTask(syncStatus: .synced, updatedAt: Date(timeIntervalSince1970: 100))
        let remote = makeRemote(updatedAt: Date(timeIntervalSince1970: 200))
        let result = ConflictResolver.resolve(
            local: local,
            localIsDeleted: false,
            localSyncStatus: .synced,
            localRemoteUpdatedAt: local.updatedAt,
            hasPendingOutbox: false,
            remote: remote
        )
        #expect(result == .applyRemote)
    }

    @Test func syncedRemoteOlderKeepsLocal() {
        let local = makeTask(syncStatus: .synced, updatedAt: Date(timeIntervalSince1970: 200))
        let remote = makeRemote(updatedAt: Date(timeIntervalSince1970: 100))
        let result = ConflictResolver.resolve(
            local: local,
            localIsDeleted: false,
            localSyncStatus: .synced,
            localRemoteUpdatedAt: local.updatedAt,
            hasPendingOutbox: false,
            remote: remote
        )
        #expect(result == .keepLocal)
    }

    @Test func noLocalAppliesRemote() {
        let remote = makeRemote()
        let result = ConflictResolver.resolve(
            local: nil,
            localIsDeleted: false,
            localSyncStatus: nil,
            localRemoteUpdatedAt: nil,
            hasPendingOutbox: false,
            remote: remote
        )
        #expect(result == .applyRemote)
    }

    @Test func pendingLocalArchiveKeepsLocalOverRemoteRestore() {
        let local = makeTask(syncStatus: .pending, isArchived: true)
        let remote = makeRemote(
            updatedAt: Date().addingTimeInterval(3600),
            isArchived: false
        )
        let result = ConflictResolver.resolve(
            local: local,
            localIsDeleted: false,
            localSyncStatus: .pending,
            localRemoteUpdatedAt: local.updatedAt,
            hasPendingOutbox: false,
            remote: remote
        )
        #expect(result == .keepLocal)
    }

    @Test func syncedRemoteRestoreAppliesOverLocalArchive() {
        let local = makeTask(
            syncStatus: .synced,
            updatedAt: Date(timeIntervalSince1970: 100),
            isArchived: true
        )
        let remote = makeRemote(
            updatedAt: Date(timeIntervalSince1970: 200),
            isArchived: false
        )
        let result = ConflictResolver.resolve(
            local: local,
            localIsDeleted: false,
            localSyncStatus: .synced,
            localRemoteUpdatedAt: local.updatedAt,
            hasPendingOutbox: false,
            remote: remote
        )
        #expect(result == .applyRemote)
    }

    private func makeTask(
        syncStatus: SyncStatus,
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) -> TaskItem {
        TaskItem(
            id: UUID(),
            title: "Local",
            taskDescription: "Desc",
            status: .todo,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: updatedAt,
            syncStatus: syncStatus,
            isArchived: isArchived,
            subtasks: []
        )
    }

    private func makeRemote(updatedAt: Date = Date(), isArchived: Bool = false) -> RemoteTaskDTO {
        RemoteTaskDTO(
            id: UUID(),
            title: "Remote",
            description: "Remote desc",
            status: .todo,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: updatedAt,
            isDeleted: false,
            isArchived: isArchived,
            subtasks: []
        )
    }
}
