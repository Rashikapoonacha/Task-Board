import Foundation

struct SyncSnapshot: Equatable, Sendable {
    var isOnline: Bool
    var isSyncing: Bool
    var pendingCount: Int
    var failedCount: Int
    var lastSyncedAt: Date?

    static let initial = SyncSnapshot(
        isOnline: true,
        isSyncing: false,
        pendingCount: 0,
        failedCount: 0,
        lastSyncedAt: nil
    )
}
