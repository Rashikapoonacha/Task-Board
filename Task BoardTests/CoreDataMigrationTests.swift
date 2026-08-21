import CoreData
import Foundation
import Testing
@testable import TaskBoard

struct CoreDataMigrationTests {

    @Test func migratingV1StoreToV2DoesNotCrashAndDefaultsSubtasksEmpty() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        guard let momdURL = Bundle(for: TaskEntity.self).url(forResource: "TaskBoardModel", withExtension: "momd") else {
            Issue.record("Missing compiled Core Data model")
            return
        }

        let v1URL = momdURL.appendingPathComponent("TaskBoardModel.mom")
        guard let v1Model = NSManagedObjectModel(contentsOf: v1URL) else {
            Issue.record("Missing v1 model")
            return
        }

        let storeDescription = NSPersistentStoreDescription(url: storeURL)
        let v1Container = NSPersistentContainer(name: "TaskBoardModel", managedObjectModel: v1Model)
        v1Container.persistentStoreDescriptions = [storeDescription]

        var v1LoadError: Error?
        v1Container.loadPersistentStores { _, error in
            v1LoadError = error
        }
        #expect(v1LoadError == nil)

        let legacyID = UUID()
        let v1Context = v1Container.viewContext
        let legacy = TaskEntity(context: v1Context)
        legacy.id = legacyID
        legacy.title = "Before upgrade"
        legacy.taskDescription = "Legacy row"
        legacy.status = TaskStatus.todo.rawValue
        legacy.sortOrder = 0
        legacy.createdAt = Date(timeIntervalSince1970: 100)
        legacy.updatedAt = Date(timeIntervalSince1970: 100)
        legacy.syncStatus = SyncStatus.synced.rawValue
        legacy.tombstoned = false
        legacy.archived = false
        try v1Context.save()

        guard let fullModel = NSManagedObjectModel(contentsOf: momdURL) else {
            Issue.record("Missing versioned model")
            return
        }

        let migratedDescription = NSPersistentStoreDescription(url: storeURL)
        migratedDescription.shouldMigrateStoreAutomatically = true
        migratedDescription.shouldInferMappingModelAutomatically = true

        let v2Container = NSPersistentContainer(name: "TaskBoardModel", managedObjectModel: fullModel)
        v2Container.persistentStoreDescriptions = [migratedDescription]

        var v2LoadError: Error?
        v2Container.loadPersistentStores { _, error in
            v2LoadError = error
        }
        #expect(v2LoadError == nil)

        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", legacyID as CVarArg)
        request.fetchLimit = 1
        let migrated = try #require(try v2Container.viewContext.fetch(request).first)
        let item = try #require(migrated.toTaskItem())

        #expect(item.title == "Before upgrade")
        #expect(item.subtasks.isEmpty)
    }
}
