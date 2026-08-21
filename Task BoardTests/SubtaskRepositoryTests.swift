import CoreData
import Foundation
import Testing
@testable import TaskBoard

struct SubtaskRepositoryTests {

    @Test func createTaskPersistsSubtasks() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let subtasks = [
            SubtaskItem(id: UUID(), title: "First", isComplete: false, sortOrder: 0),
            SubtaskItem(id: UUID(), title: "Second", isComplete: true, sortOrder: 1)
        ]
        let task = try repository.createTask(title: "Parent", description: "Body", subtasks: subtasks)
        let fetched = try #require(try repository.fetchTasks().first { $0.id == task.id })

        #expect(fetched.subtasks.count == 2)
        #expect(fetched.subtasks[0].title == "First")
        #expect(fetched.subtasks[1].isComplete == true)
    }

    @Test func updateTaskReplacesSubtasks() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let task = try repository.createTask(
            title: "Parent",
            description: "Body",
            subtasks: [SubtaskItem(id: UUID(), title: "Old", isComplete: false, sortOrder: 0)]
        )
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))

        let replacement = [SubtaskItem(id: UUID(), title: "New", isComplete: true, sortOrder: 0)]
        try repository.updateTask(id: task.id, title: "Parent", description: "Body", subtasks: replacement)

        let fetched = try #require(try repository.fetchTasks().first { $0.id == task.id })
        #expect(fetched.subtasks.count == 1)
        #expect(fetched.subtasks[0].title == "New")
        #expect(fetched.subtasks[0].isComplete == true)
    }

    @Test func updateTaskWithoutSubtasksPreservesExisting() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let subtasks = [SubtaskItem(id: UUID(), title: "Keep me", isComplete: false, sortOrder: 0)]
        let task = try repository.createTask(title: "Parent", description: "Old", subtasks: subtasks)
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))

        try repository.updateTask(id: task.id, title: "Parent", description: "New")

        let fetched = try #require(try repository.fetchTasks().first { $0.id == task.id })
        #expect(fetched.taskDescription == "New")
        #expect(fetched.subtasks.count == 1)
        #expect(fetched.subtasks[0].title == "Keep me")
    }

    @Test func legacyEntityWithoutSubtasksDataDefaultsEmpty() throws {
        let stack = try TestCoreDataStack()
        let context = stack.persistence.viewContext
        let entity = TaskEntity(context: context)
        entity.id = UUID()
        entity.title = "Legacy"
        entity.taskDescription = ""
        entity.status = TaskStatus.todo.rawValue
        entity.sortOrder = 0
        entity.createdAt = Date()
        entity.updatedAt = Date()
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.tombstoned = false
        entity.archived = false
        entity.subtasksData = nil
        try context.save()

        let item = try #require(entity.toTaskItem())
        #expect(item.subtasks.isEmpty)
    }

    @Test func archiveTaskPreservesSubtasks() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let subtasks = [SubtaskItem(id: UUID(), title: "Nested", isComplete: true, sortOrder: 0)]
        let task = try repository.createTask(title: "Parent", description: "", subtasks: subtasks)
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))

        try repository.archiveTask(id: task.id)
        let fetched = try #require(try repository.fetchTasks().first { $0.id == task.id })
        #expect(fetched.isArchived == true)
        #expect(fetched.subtasks.count == 1)

        try repository.unarchiveTask(id: task.id)
        let restored = try #require(try repository.fetchTasks().first { $0.id == task.id })
        #expect(restored.isArchived == false)
        #expect(restored.subtasks.first?.title == "Nested")
    }

    @Test func remoteMappingMissingSubtasksDefaultsEmpty() {
        let dto = RemoteTaskMapping.makeDTO(from: [
            "id": UUID().uuidString,
            "title": "Remote",
            "description": "",
            "status": TaskStatus.todo.rawValue,
            "sortOrder": 0,
            "createdAt": Date(),
            "updatedAt": Date(),
            "deleted": false,
            "archived": false
        ]) { value in
            value as? Date
        }

        #expect(dto?.subtasks.isEmpty == true)
    }
}
