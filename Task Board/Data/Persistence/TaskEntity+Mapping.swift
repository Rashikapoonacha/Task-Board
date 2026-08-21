import CoreData
import Foundation

extension TaskEntity {
    func toTaskItem() -> TaskItem? {
        guard let id, let title, let taskDescription, let statusRaw = status,
              let status = TaskStatus(rawValue: statusRaw),
              let createdAt, let updatedAt,
              let syncStatusRaw = syncStatus,
              let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
            return nil
        }

        return TaskItem(
            id: id,
            title: title,
            taskDescription: taskDescription,
            status: status,
            sortOrder: Int(sortOrder),
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: syncStatus,
            isArchived: archived
        )
    }

    func toRemoteDTO() -> RemoteTaskDTO? {
        guard let id, let title, let taskDescription, let statusRaw = status,
              let status = TaskStatus(rawValue: statusRaw),
              let createdAt, let updatedAt else {
            return nil
        }

        return RemoteTaskDTO(
            id: id,
            title: title,
            description: taskDescription,
            status: status,
            sortOrder: Int(sortOrder),
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: tombstoned,
            isArchived: archived,
            baseRemoteUpdatedAt: remoteUpdatedAt
        )
    }

    func apply(dto: RemoteTaskDTO) {
        title = dto.title
        taskDescription = dto.description
        status = dto.status.rawValue
        sortOrder = Int32(dto.sortOrder)
        updatedAt = dto.updatedAt
        remoteUpdatedAt = dto.updatedAt
        tombstoned = dto.isDeleted
        archived = dto.isArchived
        syncStatus = SyncStatus.synced.rawValue
    }
}

extension SyncOperationEntity {
    func toSyncOperation() -> SyncOperation? {
        guard let id, let taskId, let kindRaw = kind,
              let kind = SyncOperationKind(rawValue: kindRaw),
              let enqueuedAt else {
            return nil
        }

        return SyncOperation(
            id: id,
            taskId: taskId,
            kind: kind,
            enqueuedAt: enqueuedAt,
            attemptCount: Int(attemptCount),
            nextRetryAt: nextRetryAt,
            lastError: lastError
        )
    }
}
