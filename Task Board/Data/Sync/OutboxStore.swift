import CoreData
import Foundation

final class OutboxStore: OutboxStoreProtocol {
    private let context: () -> NSManagedObjectContext

    init(context: @escaping () -> NSManagedObjectContext) {
        self.context = context
    }

    func enqueue(taskId: UUID, kind: SyncOperationKind) throws {
        try perform { ctx in
            try self.coalesce(for: taskId, newKind: kind, in: ctx)
        }
    }

    func fetchReady(now: Date) throws -> [SyncOperation] {
        try perform { ctx in
            let request = SyncOperationEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "enqueuedAt", ascending: true)]
            let entities = try ctx.fetch(request)
            return entities.compactMap { entity -> SyncOperation? in
                guard let op = entity.toSyncOperation() else { return nil }
                if let nextRetryAt = op.nextRetryAt, nextRetryAt > now {
                    return nil
                }
                return op
            }
        }
    }

    func remove(id: UUID) throws {
        try perform { ctx in
            let request = SyncOperationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let entity = try ctx.fetch(request).first {
                ctx.delete(entity)
            }
        }
    }

    func recordFailure(id: UUID, error: String, nextRetryAt: Date) throws {
        try perform { ctx in
            let request = SyncOperationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else { return }
            entity.attemptCount += 1
            entity.lastError = error
            entity.nextRetryAt = nextRetryAt
        }
    }

    func resetRetryState() throws {
        try perform { ctx in
            let request = SyncOperationEntity.fetchRequest()
            let entities = try ctx.fetch(request)
            for entity in entities {
                entity.nextRetryAt = nil
            }
        }
    }

    func pendingCount() throws -> Int {
        try perform { ctx in
            let request = SyncOperationEntity.fetchRequest()
            return try ctx.count(for: request)
        }
    }

    func hasPendingOperation(for taskId: UUID) throws -> Bool {
        try perform { ctx in
            let request = SyncOperationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "taskId == %@", taskId as CVarArg)
            request.fetchLimit = 1
            return try ctx.count(for: request) > 0
        }
    }

    // MARK: - Private

    private func perform<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        let ctx = context()
        var result: T!
        var thrown: Error?
        ctx.performAndWait {
            do {
                result = try work(ctx)
                if ctx.hasChanges {
                    try ctx.save()
                }
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
        return result
    }

    private func coalesce(for taskId: UUID, newKind: SyncOperationKind, in ctx: NSManagedObjectContext) throws {
        let request = SyncOperationEntity.fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", taskId as CVarArg)
        let existing = try ctx.fetch(request)

        if newKind == .delete {
            for entity in existing {
                ctx.delete(entity)
            }
            insert(taskId: taskId, kind: .delete, in: ctx)
            return
        }

        if let current = existing.first {
            switch (SyncOperationKind(rawValue: current.kind ?? ""), newKind) {
            case (.create, .update):
                return
            case (.create, .delete):
                for entity in existing { ctx.delete(entity) }
                try purgeUnsyncedTask(taskId: taskId, in: ctx)
                return
            case (.update, .update):
                return
            case (.update, .delete):
                ctx.delete(current)
                insert(taskId: taskId, kind: .delete, in: ctx)
                return
            default:
                ctx.delete(current)
                insert(taskId: taskId, kind: newKind, in: ctx)
            }
        } else {
            insert(taskId: taskId, kind: newKind, in: ctx)
        }
    }

    private func insert(taskId: UUID, kind: SyncOperationKind, in ctx: NSManagedObjectContext) {
        let entity = SyncOperationEntity(context: ctx)
        entity.id = UUID()
        entity.taskId = taskId
        entity.kind = kind.rawValue
        entity.enqueuedAt = Date()
        entity.attemptCount = 0
        entity.nextRetryAt = nil
        entity.lastError = nil
    }

    private func purgeUnsyncedTask(taskId: UUID, in ctx: NSManagedObjectContext) throws {
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", taskId as CVarArg)
        request.fetchLimit = 1
        if let task = try ctx.fetch(request).first,
           task.syncStatus == SyncStatus.pending.rawValue {
            ctx.delete(task)
        }
    }
}
