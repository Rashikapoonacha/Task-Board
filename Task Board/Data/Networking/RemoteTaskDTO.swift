import Foundation

struct RemoteTaskDTO: Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var description: String
    var status: TaskStatus
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    /// Last remote `updatedAt` this device had observed when the local mutation was made.
    /// Not persisted to Firestore.
    var baseRemoteUpdatedAt: Date? = nil
}

enum RemoteTaskMapping {
    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let int64 = value as? Int64 {
            return Int(int64)
        }
        if let int32 = value as? Int32 {
            return Int(int32)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    static func makeDTO(from data: [String: Any], date: (Any?) -> Date?) -> RemoteTaskDTO? {
        guard
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let title = data["title"] as? String,
            let description = data["description"] as? String,
            let statusRaw = data["status"] as? String,
            let status = TaskStatus(rawValue: statusRaw),
            let sortOrder = intValue(data["sortOrder"]),
            let createdAt = date(data["createdAt"]),
            let updatedAt = date(data["updatedAt"])
        else {
            return nil
        }

        let isDeleted = data["deleted"] as? Bool ?? false
        return RemoteTaskDTO(
            id: id,
            title: title,
            description: description,
            status: status,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}
