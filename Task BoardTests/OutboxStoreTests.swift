import CoreData
import Foundation
import Testing
@testable import TaskBoard

struct OutboxStoreTests {

    @Test func createEnqueueProducesOneEntry() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let taskId = UUID()

        try outbox.enqueue(taskId: taskId, kind: .create)
        let ops = try outbox.fetchReady(now: Date())

        #expect(ops.count == 1)
        #expect(ops.first?.kind == .create)
    }

    @Test func createPlusUpdateCoalescesToCreate() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let taskId = UUID()

        try outbox.enqueue(taskId: taskId, kind: .create)
        try outbox.enqueue(taskId: taskId, kind: .update)
        let ops = try outbox.fetchReady(now: Date())

        #expect(ops.count == 1)
        #expect(ops.first?.kind == .create)
    }

    @Test func updatePlusDeleteCoalescesToDelete() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let taskId = UUID()

        try outbox.enqueue(taskId: taskId, kind: .update)
        try outbox.enqueue(taskId: taskId, kind: .delete)
        let ops = try outbox.fetchReady(now: Date())

        #expect(ops.count == 1)
        #expect(ops.first?.kind == .delete)
    }

    @Test func fetchReadyRespectsBackoff() throws {
        let stack = try TestCoreDataStack()
        let outbox = OutboxStore { stack.writeContext }
        let taskId = UUID()
        try outbox.enqueue(taskId: taskId, kind: .create)

        let ops = try outbox.fetchReady(now: Date())
        let opId = try #require(ops.first?.id)
        try outbox.recordFailure(id: opId, error: "fail", nextRetryAt: Date().addingTimeInterval(3600))

        let readyNow = try outbox.fetchReady(now: Date())
        #expect(readyNow.isEmpty)
    }
}

final class TestCoreDataStack {
    let persistence: PersistenceController

    init() throws {
        persistence = PersistenceController(inMemory: true)
    }

    var writeContext: NSManagedObjectContext { persistence.writeContext }
}
