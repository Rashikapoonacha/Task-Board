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
}
