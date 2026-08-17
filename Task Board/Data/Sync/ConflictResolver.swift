import Foundation

enum ConflictResolution: Equatable {
    case applyRemote
    case keepLocal
}

enum ConflictResolver {
    /// Remote pull must never overwrite a local task with an unacknowledged pending mutation.
    static func resolve(
        local: TaskItem?,
        localIsDeleted: Bool,
        localSyncStatus: SyncStatus?,
        localRemoteUpdatedAt: Date?,
        hasPendingOutbox: Bool,
        remote: RemoteTaskDTO
    ) -> ConflictResolution {
        if hasPendingOutbox || localSyncStatus == .pending || localSyncStatus == .failed {
            return .keepLocal
        }

        guard let local else {
            return remote.isDeleted ? .keepLocal : .applyRemote
        }

        if localIsDeleted {
            return .keepLocal
        }

        if remote.isDeleted {
            return .applyRemote
        }

        if local.syncStatus == .synced {
            let localTimestamp = localRemoteUpdatedAt ?? local.updatedAt
            if remote.updatedAt > localTimestamp {
                return .applyRemote
            }
            return .keepLocal
        }

        return .keepLocal
    }
}
