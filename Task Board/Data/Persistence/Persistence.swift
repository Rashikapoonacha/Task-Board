import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    let writeContext: NSManagedObjectContext

    var viewContext: NSManagedObjectContext { container.viewContext }

    var backgroundContext: NSManagedObjectContext { writeContext }

    @MainActor
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        let statuses: [TaskStatus] = [.todo, .inProgress, .done]
        for (index, status) in statuses.enumerated() {
            let entity = TaskEntity(context: context)
            entity.id = UUID()
            entity.title = "Sample \(status.displayName)"
            entity.taskDescription = "Preview task"
            entity.status = status.rawValue
            entity.sortOrder = Int32(index)
            entity.createdAt = Date()
            entity.updatedAt = Date()
            entity.syncStatus = SyncStatus.synced.rawValue
            entity.tombstoned = false
            entity.archived = false
        }
        try? context.save()
        return controller
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "TaskBoardModel")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.persistentStoreDescriptions.forEach { description in
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Unresolved Core Data error: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        writeContext = context
    }

}
