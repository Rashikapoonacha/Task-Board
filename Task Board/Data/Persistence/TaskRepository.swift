import CoreData
import Foundation

final class TaskRepository: TaskRepositoryProtocol {
    private let persistence: PersistenceController
    private let outbox: OutboxStoreProtocol
    private var onMutation: (() -> Void)?

    private var viewContext: NSManagedObjectContext { persistence.viewContext }

    init(persistence: PersistenceController, outbox: OutboxStoreProtocol) {
        self.persistence = persistence
        self.outbox = outbox
    }

    func setOnMutation(_ handler: @escaping () -> Void) {
        onMutation = handler
    }

    func fetchTasks() throws -> [TaskItem] {
        try fetchTaskEntities().compactMap { $0.toTaskItem() }
    }

    func observeTasks() -> AsyncStream<[TaskItem]> {
        AsyncStream { continuation in
            continuation.yield((try? fetchTasks()) ?? [])

            let writeContext = persistence.writeContext
            let viewContext = self.viewContext
            let observer = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: writeContext,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                viewContext.perform {
                    viewContext.refreshAllObjects()
                    continuation.yield((try? self.fetchTasks()) ?? [])
                }
            }

            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func createTask(title: String, description: String) throws -> TaskItem {
        try createTask(title: title, description: description, subtasks: [])
    }

    func createTask(title: String, description: String, subtasks: [SubtaskItem]) throws -> TaskItem {
        let now = Date()
        let taskId = UUID()
        var created: TaskItem!

        try performWrite { ctx in
            let status = TaskStatus.todo
            let count = try self.activeTasks(in: status, context: ctx).count
            let entity = TaskEntity(context: ctx)
            entity.id = taskId
            entity.title = title
            entity.taskDescription = description
            entity.status = status.rawValue
            entity.sortOrder = Int32(count)
            entity.createdAt = now
            entity.updatedAt = now
            entity.syncStatus = SyncStatus.pending.rawValue
            entity.tombstoned = false
            entity.archived = false
            entity.subtasksData = SubtaskStorage.encode(subtasks)
            try self.outbox.enqueue(taskId: taskId, kind: .create)
            guard let item = entity.toTaskItem() else {
                throw RepositoryError.mappingFailed
            }
            created = item
        }

        notifyMutation()
        return created
    }

    func updateTask(id: UUID, title: String, description: String) throws {
        try updateTask(id: id, title: title, description: description, subtasks: nil)
    }

    func updateTask(id: UUID, title: String, description: String, subtasks: [SubtaskItem]?) throws {
        try performWrite { ctx in
            let entity = try self.taskEntity(id: id, in: ctx)
            entity.title = title
            entity.taskDescription = description
            if let subtasks {
                entity.subtasksData = SubtaskStorage.encode(subtasks)
            }
            entity.updatedAt = Date()
            entity.syncStatus = SyncStatus.pending.rawValue
            try self.enqueueMutation(for: entity, in: ctx)
        }
        notifyMutation()
    }

    func moveTask(id: UUID, to status: TaskStatus, at index: Int) throws {
        try performWrite { ctx in
            let entity = try self.taskEntity(id: id, in: ctx)
            let oldStatus = TaskStatus(rawValue: entity.status ?? "") ?? .todo
            entity.status = status.rawValue
            entity.updatedAt = Date()
            entity.syncStatus = SyncStatus.pending.rawValue

            var destination = try self.activeTasks(in: status, context: ctx).filter { $0.id != id }
            let clampedIndex = min(max(index, 0), destination.count)
            destination.insert(entity, at: clampedIndex)
            self.renumber(tasks: destination)

            if oldStatus != status {
                let source = try self.activeTasks(in: oldStatus, context: ctx)
                self.renumber(tasks: source)
            }

            try self.enqueueMutation(for: entity, in: ctx)
        }
        notifyMutation()
    }

    func reorderTasks(in status: TaskStatus, orderedIDs: [UUID]) throws {
        try performWrite { ctx in
            let tasks = try self.activeTasks(in: status, context: ctx)
            let map = Dictionary(uniqueKeysWithValues: tasks.compactMap { entity -> (UUID, TaskEntity)? in
                guard let id = entity.id else { return nil }
                return (id, entity)
            })

            for (index, taskId) in orderedIDs.enumerated() {
                guard let entity = map[taskId] else { continue }
                entity.sortOrder = Int32(index)
                entity.updatedAt = Date()
                entity.syncStatus = SyncStatus.pending.rawValue
                try self.enqueueMutation(for: entity, in: ctx)
            }
        }
        notifyMutation()
    }

    func deleteTask(id: UUID) throws {
        try performWrite { ctx in
            let entity = try self.taskEntity(id: id, in: ctx)
            let status = TaskStatus(rawValue: entity.status ?? "") ?? .todo
            entity.tombstoned = true
            entity.updatedAt = Date()
            entity.syncStatus = SyncStatus.pending.rawValue
            try self.outbox.enqueue(taskId: id, kind: .delete)

            let remaining = try self.activeTasks(in: status, context: ctx)
            self.renumber(tasks: remaining)
        }
        notifyMutation()
    }

    func archiveTask(id: UUID) throws {
        try performWrite { ctx in
            let entity = try self.taskEntity(id: id, in: ctx)
            let status = TaskStatus(rawValue: entity.status ?? "") ?? .todo
            entity.archived = true
            entity.updatedAt = Date()
            entity.syncStatus = SyncStatus.pending.rawValue
            try self.enqueueMutation(for: entity, in: ctx)

            let remaining = try self.activeTasks(in: status, context: ctx)
            self.renumber(tasks: remaining)
        }
        notifyMutation()
    }

    func unarchiveTask(id: UUID) throws {
        try performWrite { ctx in
            let entity = try self.taskEntity(id: id, in: ctx)
            let status = TaskStatus(rawValue: entity.status ?? "") ?? .todo
            entity.archived = false
            entity.sortOrder = Int32(try self.activeTasks(in: status, context: ctx).count)
            entity.updatedAt = Date()
            entity.syncStatus = SyncStatus.pending.rawValue
            try self.enqueueMutation(for: entity, in: ctx)
        }
        notifyMutation()
    }

    func applyRemoteTask(_ dto: RemoteTaskDTO) throws {
        try performWrite { ctx in
            let request = TaskEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
            request.fetchLimit = 1
            let entity = try ctx.fetch(request).first ?? TaskEntity(context: ctx)

            if entity.id == nil {
                entity.id = dto.id
                entity.createdAt = dto.createdAt
            }

            entity.apply(dto: dto)
            if dto.isDeleted {
                entity.tombstoned = true
            }
        }
    }

    func markSynced(taskId: UUID, remoteUpdatedAt: Date) throws {
        try performWrite { ctx in
            let entity = try self.taskEntity(id: taskId, in: ctx)
            entity.syncStatus = SyncStatus.synced.rawValue
            entity.remoteUpdatedAt = remoteUpdatedAt
        }
    }

    func markFailed(taskId: UUID) throws {
        try performWrite { ctx in
            let entity = try self.taskEntity(id: taskId, in: ctx)
            entity.syncStatus = SyncStatus.failed.rawValue
        }
    }

    func taskEntitySnapshot(for taskId: UUID) throws -> RemoteTaskDTO? {
        try performRead { ctx in
            let request = TaskEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", taskId as CVarArg)
            request.fetchLimit = 1
            return try ctx.fetch(request).first?.toRemoteDTO()
        }
    }

    func lastPullAt() throws -> Date? {
        try performRead { ctx in
            let request = SyncMetadataEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", "singleton")
            request.fetchLimit = 1
            return try ctx.fetch(request).first?.lastPullAt
        }
    }

    func setLastPullAt(_ date: Date) throws {
        try performWrite { ctx in
            let entity = try self.metadata(in: ctx)
            entity.lastPullAt = date
        }
    }

    func pendingSyncCount() throws -> Int {
        try outbox.pendingCount()
    }

    func failedSyncCount() throws -> Int {
        try performRead { ctx in
            let request = TaskEntity.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %@", SyncStatus.failed.rawValue)
            return try ctx.count(for: request)
        }
    }

    func localTaskState(for taskId: UUID) throws -> (TaskItem?, Bool, SyncStatus?, Date?, Bool) {
        let hasPending = try outbox.hasPendingOperation(for: taskId)
        return try performRead { ctx in
            let request = TaskEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", taskId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                return (nil, false, nil, nil, hasPending)
            }
            let syncStatus = SyncStatus(rawValue: entity.syncStatus ?? "")
            return (
                entity.toTaskItem(),
                entity.tombstoned,
                syncStatus,
                entity.remoteUpdatedAt,
                hasPending
            )
        }
    }

    // MARK: - Private

    private enum RepositoryError: Error {
        case notFound
        case mappingFailed
    }

    private func performRead<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        let ctx = persistence.backgroundContext
        var result: T!
        var thrown: Error?
        ctx.performAndWait {
            do {
                result = try work(ctx)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
        return result
    }

    private func performWrite(_ work: (NSManagedObjectContext) throws -> Void) throws {
        let ctx = persistence.backgroundContext
        var thrown: Error?
        ctx.performAndWait {
            do {
                try work(ctx)
                if ctx.hasChanges {
                    try ctx.save()
                }
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    private func fetchTaskEntities() throws -> [TaskEntity] {
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "tombstoned == NO")
        request.sortDescriptors = [
            NSSortDescriptor(key: "status", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true)
        ]
        return try viewContext.fetch(request)
    }

    private func activeTasks(in status: TaskStatus, context: NSManagedObjectContext) throws -> [TaskEntity] {
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "tombstoned == NO AND archived == NO AND status == %@",
            status.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request)
    }

    private func taskEntity(id: UUID, in context: NSManagedObjectContext) throws -> TaskEntity {
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try context.fetch(request).first else {
            throw RepositoryError.notFound
        }
        return entity
    }

    private func renumber(tasks: [TaskEntity]) {
        for (index, task) in tasks.enumerated() {
            task.sortOrder = Int32(index)
        }
    }

    private func enqueueMutation(for entity: TaskEntity, in ctx: NSManagedObjectContext) throws {
        guard let id = entity.id else { return }
        let kind: SyncOperationKind
        if entity.syncStatus == SyncStatus.pending.rawValue {
            let request = SyncOperationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "taskId == %@", id as CVarArg)
            request.fetchLimit = 1
            if let existing = try ctx.fetch(request).first,
               existing.kind == SyncOperationKind.create.rawValue {
                kind = .create
            } else {
                kind = .update
            }
        } else {
            kind = .update
        }
        try outbox.enqueue(taskId: id, kind: kind)
    }

    private func metadata(in context: NSManagedObjectContext) throws -> SyncMetadataEntity {
        let request = SyncMetadataEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", "singleton")
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let entity = SyncMetadataEntity(context: context)
        entity.id = "singleton"
        return entity
    }

    private func notifyMutation() {
        onMutation?()
    }
}
