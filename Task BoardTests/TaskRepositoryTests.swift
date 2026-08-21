import Foundation
import Testing
@testable import TaskBoard

struct TaskRepositoryTests {

    @Test func createTaskPersistsPendingWithOutbox() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let task = try repository.createTask(title: "Test", description: "Body")
        let tasks = try repository.fetchTasks()

        #expect(tasks.count == 1)
        #expect(tasks.first?.title == "Test")
        #expect(tasks.first?.syncStatus == .pending)
        #expect(try outbox.pendingCount() == 1)
        #expect(task.id == tasks.first?.id)
    }

    @Test func deleteTaskTombstonesAndEnqueuesDelete() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let task = try repository.createTask(title: "Delete me", description: "")
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))

        try repository.deleteTask(id: task.id)
        let visible = try repository.fetchTasks()
        #expect(visible.isEmpty)

        let ops = try outbox.fetchReady(now: Date())
        #expect(ops.first?.kind == .delete)
    }

    @Test func reorderRenumbersSortOrder() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let first = try repository.createTask(title: "A", description: "")
        let second = try repository.createTask(title: "B", description: "")

        try repository.reorderTasks(in: .todo, orderedIDs: [second.id, first.id])
        let tasks = try repository.fetchTasks()

        #expect(tasks.first?.id == second.id)
        #expect(tasks.first?.sortOrder == 0)
        #expect(tasks.last?.sortOrder == 1)
    }

    @Test func updateTaskPublishesImmediatelyViaObserveTasks() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let task = try repository.createTask(title: "Old", description: "before")
        let stream = repository.observeTasks()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        try repository.updateTask(id: task.id, title: "New", description: "after")

        let updated = await iterator.next()
        #expect(updated?.first?.title == "New")
        #expect(updated?.first?.taskDescription == "after")
        #expect(updated?.first?.syncStatus == .pending)
    }

    @Test func archiveTaskMarksArchivedAndEnqueuesUpdate() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let task = try repository.createTask(title: "Archive me", description: "")
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))

        try repository.archiveTask(id: task.id)
        let fetched = try repository.fetchTasks()

        #expect(fetched.count == 1)
        #expect(fetched.first?.isArchived == true)

        let ops = try outbox.fetchReady(now: Date())
        #expect(ops.first?.kind == .update)
    }

    @Test func unarchiveTaskRestoresToActiveList() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let task = try repository.createTask(title: "Restore me", description: "")
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))

        try repository.archiveTask(id: task.id)
        try repository.unarchiveTask(id: task.id)

        let fetched = try repository.fetchTasks()
        #expect(fetched.count == 1)
        #expect(fetched.first?.isArchived == false)
        #expect(fetched.first?.status == .todo)
    }

    @Test func archiveTaskRenumbersRemainingTasks() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let first = try repository.createTask(title: "A", description: "")
        let second = try repository.createTask(title: "B", description: "")
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))
        try outbox.remove(id: try #require(try outbox.fetchReady(now: Date()).first?.id))

        try repository.archiveTask(id: first.id)

        let active = try repository.fetchTasks().filter { !$0.isArchived }
        #expect(active.count == 1)
        #expect(active.first?.id == second.id)
        #expect(active.first?.sortOrder == 0)
    }

    @Test func observeTasksEmitsArchiveAndRestore() async throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let repository = TaskRepository(persistence: stack.persistence, outbox: outbox)

        let task = try repository.createTask(title: "Stream", description: "")
        let stream = repository.observeTasks()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        try repository.archiveTask(id: task.id)
        let archivedSnapshot = await iterator.next()
        #expect(archivedSnapshot?.first?.isArchived == true)

        try repository.unarchiveTask(id: task.id)
        let restoredSnapshot = await iterator.next()
        #expect(restoredSnapshot?.first?.isArchived == false)
    }
}
