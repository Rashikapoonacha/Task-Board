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

    private func makeTask(syncStatus: SyncStatus, updatedAt: Date = Date()) -> TaskItem {
        TaskItem(
            id: UUID(),
            title: "Local",
            taskDescription: "Desc",
            status: .todo,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: updatedAt,
            syncStatus: syncStatus
        )
    }

    private func makeRemote(updatedAt: Date = Date()) -> RemoteTaskDTO {
        RemoteTaskDTO(
            id: UUID(),
            title: "Remote",
            description: "Remote desc",
            status: .todo,
            sortOrder: 0,
            createdAt: Date(),
            updatedAt: updatedAt,
            isDeleted: false
        )
    }
}
