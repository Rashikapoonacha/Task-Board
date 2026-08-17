import Foundation
import Testing
@testable import TaskBoard

struct PullWatermarkTests {
    @Test func emptyFetchDoesNotAdvanceToDeviceNow() {
        let previous = Date(timeIntervalSince1970: 50)
        let next = PullWatermark.next(previous: previous, fetchedUpdatedAt: [])
        #expect(next == previous)
    }

    @Test func firstEmptyFetchLeavesNilWatermark() {
        #expect(PullWatermark.next(previous: nil, fetchedUpdatedAt: []) == nil)
    }

    @Test func watermarkIsMaxFetchedUpdatedAt() {
        let dates = [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 40),
            Date(timeIntervalSince1970: 25)
        ]
        #expect(PullWatermark.next(previous: nil, fetchedUpdatedAt: dates) == Date(timeIntervalSince1970: 40))
    }
}

struct RemoteTaskMappingTests {
    @Test func sortOrderAcceptsInt64AndNSNumber() {
        #expect(RemoteTaskMapping.intValue(Int64(7)) == 7)
        #expect(RemoteTaskMapping.intValue(NSNumber(value: 12)) == 12)
        #expect(RemoteTaskMapping.intValue(3) == 3)
    }

    @Test func dtoIsNotDroppedWhenSortOrderIsInt64() {
        let id = UUID()
        let data: [String: Any] = [
            "id": id.uuidString,
            "title": "X",
            "description": "d",
            "status": TaskStatus.todo.rawValue,
            "sortOrder": Int64(4),
            "createdAt": Date(timeIntervalSince1970: 1),
            "updatedAt": Date(timeIntervalSince1970: 2),
            "deleted": false
        ]
        let dto = RemoteTaskMapping.makeDTO(from: data) { $0 as? Date }
        #expect(dto?.id == id)
        #expect(dto?.sortOrder == 4)
    }
}

struct RemoteConcurrencyTests {
    @Test func createSucceedsWhenRemoteMissing() {
        let incoming = TestTaskFactory.remote(title: "New", updatedAt: Date(timeIntervalSince1970: 1))
        let result = RemoteConcurrency.create(existing: nil, incoming: incoming)
        #expect(result == .success(incoming))
    }

    @Test func createConflictsWhenRemoteExists() {
        let existing = TestTaskFactory.remote(title: "There", updatedAt: Date(timeIntervalSince1970: 2))
        let incoming = TestTaskFactory.remote(id: existing.id, title: "New", updatedAt: Date(timeIntervalSince1970: 1))
        let result = RemoteConcurrency.create(existing: existing, incoming: incoming)
        #expect(result == .conflict(existing))
    }

    @Test func updateConflictsWhenRemoteNewerThanBase() {
        let base = Date(timeIntervalSince1970: 10)
        let existing = TestTaskFactory.remote(
            title: "B edited",
            updatedAt: Date(timeIntervalSince1970: 20),
            baseRemoteUpdatedAt: base
        )
        var incoming = TestTaskFactory.remote(
            id: existing.id,
            title: "A edited",
            updatedAt: Date(timeIntervalSince1970: 15),
            baseRemoteUpdatedAt: base
        )
        incoming.baseRemoteUpdatedAt = base
        let result = RemoteConcurrency.update(existing: existing, incoming: incoming)
        #expect(result == .conflict(existing))
    }

    @Test func deleteConflictsWhenRemoteIsNewerEdit() {
        let base = Date(timeIntervalSince1970: 10)
        let existing = TestTaskFactory.remote(
            title: "B edited",
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        var incoming = TestTaskFactory.remote(
            id: existing.id,
            title: "A",
            updatedAt: Date(timeIntervalSince1970: 12),
            isDeleted: true,
            baseRemoteUpdatedAt: base
        )
        incoming.baseRemoteUpdatedAt = base
        let result = RemoteConcurrency.delete(existing: existing, incoming: incoming)
        #expect(result == .conflict(existing))
    }
}
