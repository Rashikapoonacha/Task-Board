import Foundation

protocol OutboxStoreProtocol: AnyObject {
    func enqueue(taskId: UUID, kind: SyncOperationKind) throws
    func fetchReady(now: Date) throws -> [SyncOperation]
    func remove(id: UUID) throws
    func recordFailure(id: UUID, error: String, nextRetryAt: Date) throws
    func resetRetryState() throws
    func pendingCount() throws -> Int
    func hasPendingOperation(for taskId: UUID) throws -> Bool
}
