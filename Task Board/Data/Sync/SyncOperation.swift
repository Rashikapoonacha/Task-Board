import Foundation

struct SyncOperation: Identifiable, Equatable, Sendable {
    let id: UUID
    let taskId: UUID
    let kind: SyncOperationKind
    let enqueuedAt: Date
    var attemptCount: Int
    var nextRetryAt: Date?
    var lastError: String?
}
