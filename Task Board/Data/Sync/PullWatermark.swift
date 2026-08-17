import Foundation

enum PullWatermark {
    /// Incremental pull must track the newest *remote* `updatedAt` we have actually seen.
    /// Using `Date()` (device now) can sit ahead of client timestamps from offline creates,
    /// so those documents never match `updatedAt > lastPullAt`.
    static func next(previous: Date?, fetchedUpdatedAt: [Date]) -> Date? {
        if let newest = fetchedUpdatedAt.max() {
            return newest
        }
        return previous
    }
}
