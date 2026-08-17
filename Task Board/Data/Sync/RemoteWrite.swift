import Foundation

enum RemoteMutationResult: Equatable, Sendable {
    case success(RemoteTaskDTO)
    case conflict(RemoteTaskDTO)
}

enum RemoteConcurrency {
    /// Optimistic concurrency: the remote document changed after this device last observed it.
    static func isStaleBase(remoteUpdatedAt: Date, baseRemoteUpdatedAt: Date?) -> Bool {
        guard let baseRemoteUpdatedAt else {
            return true
        }
        return remoteUpdatedAt > baseRemoteUpdatedAt
    }

    static func create(existing: RemoteTaskDTO?, incoming: RemoteTaskDTO) -> RemoteMutationResult {
        if let existing {
            return .conflict(existing)
        }
        return .success(incoming)
    }

    static func update(existing: RemoteTaskDTO?, incoming: RemoteTaskDTO) -> RemoteMutationResult {
        guard let existing else {
            return .success(incoming)
        }
        if isStaleBase(remoteUpdatedAt: existing.updatedAt, baseRemoteUpdatedAt: incoming.baseRemoteUpdatedAt) {
            return .conflict(existing)
        }
        return .success(incoming)
    }

    static func delete(existing: RemoteTaskDTO?, incoming: RemoteTaskDTO) -> RemoteMutationResult {
        guard let existing else {
            var deleted = incoming
            deleted.isDeleted = true
            return .success(deleted)
        }
        if isStaleBase(remoteUpdatedAt: existing.updatedAt, baseRemoteUpdatedAt: incoming.baseRemoteUpdatedAt) {
            return .conflict(existing)
        }
        var deleted = incoming
        deleted.isDeleted = true
        return .success(deleted)
    }
}
