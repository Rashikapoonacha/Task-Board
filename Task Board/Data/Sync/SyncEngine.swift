import Foundation

actor SyncEngine {
    private let repository: TaskRepository
    private let outbox: OutboxStoreProtocol
    private let remote: TaskRemoteServiceProtocol
    private let isOnline: () -> Bool

    private var isSyncing = false
    private var debounceTask: Task<Void, Never>?
    private var snapshot = SyncSnapshot.initial
    private var continuations: [UUID: AsyncStream<SyncSnapshot>.Continuation] = [:]

    private let maxAttempts = 5

    init(
        repository: TaskRepository,
        outbox: OutboxStoreProtocol,
        remote: TaskRemoteServiceProtocol,
        isOnline: @escaping () -> Bool
    ) {
        self.repository = repository
        self.outbox = outbox
        self.remote = remote
        self.isOnline = isOnline
    }

    func requestSync() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await syncNow(forceWhenOffline: false)
        }
    }

    func syncNow(forceWhenOffline: Bool = true) async {
        if isSyncing { return }
        if !isOnline(), !forceWhenOffline { return }

        isSyncing = true
        await publishSnapshot(isSyncing: true)

        defer {
            isSyncing = false
        }

        var lastSyncedAt: Date?
        do {
            try await pushPendingOperations()
            try await pullRemoteChanges()
            lastSyncedAt = Date()
        } catch {
            lastSyncedAt = nil
        }

        await publishSnapshot(isSyncing: false, lastSyncedAt: lastSyncedAt)
    }

    func observeSyncState() -> AsyncStream<SyncSnapshot> {
        let id = UUID()
        return AsyncStream(SyncSnapshot.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            Task {
                await self.registerContinuation(id: id, continuation: continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    func setOnline(_ online: Bool) async {
        snapshot.isOnline = online
        await publishSnapshot()
        if online {
            requestSync()
        }
    }

    // MARK: - Private

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func registerContinuation(id: UUID, continuation: AsyncStream<SyncSnapshot>.Continuation) {
        continuations[id] = continuation
        continuation.yield(snapshot)
    }

    private func pushPendingOperations() async throws {
        let now = Date()
        let operations = try outbox.fetchReady(now: now)

        for operation in operations {
            guard let dto = try repository.taskEntitySnapshot(for: operation.taskId) else {
                try outbox.remove(id: operation.id)
                continue
            }

            do {
                let result: RemoteMutationResult
                switch operation.kind {
                case .create:
                    result = try await remote.createTask(dto, idempotencyKey: operation.id)
                case .update:
                    result = try await remote.updateTask(dto, idempotencyKey: operation.id)
                case .delete:
                    result = try await remote.deleteTask(dto, idempotencyKey: operation.id)
                }

                switch result {
                case .success(let written):
                    try repository.markSynced(taskId: operation.taskId, remoteUpdatedAt: written.updatedAt)
                    try outbox.remove(id: operation.id)
                case .conflict(let remoteTask):
                    try repository.applyRemoteTask(remoteTask)
                    try outbox.remove(id: operation.id)
                }
            } catch {
                let nextAttempt = operation.attemptCount + 1
                if nextAttempt >= maxAttempts {
                    try repository.markFailed(taskId: operation.taskId)
                    let backoff = backoffDate(for: nextAttempt)
                    try outbox.recordFailure(id: operation.id, error: error.localizedDescription, nextRetryAt: backoff)
                } else {
                    let backoff = backoffDate(for: nextAttempt)
                    try outbox.recordFailure(id: operation.id, error: error.localizedDescription, nextRetryAt: backoff)
                }
            }
        }
    }

    private func pullRemoteChanges() async throws {
        let lastPull = try repository.lastPullAt()
        let remoteTasks = try await remote.fetchTasks(updatedSince: lastPull)

        for remote in remoteTasks {
            let state = try repository.localTaskState(for: remote.id)
            let resolution = ConflictResolver.resolve(
                local: state.0,
                localIsDeleted: state.1,
                localSyncStatus: state.2,
                localRemoteUpdatedAt: state.3,
                hasPendingOutbox: state.4,
                remote: remote
            )

            if resolution == .applyRemote {
                try repository.applyRemoteTask(remote)
            }
        }

        let watermark = PullWatermark.next(
            previous: lastPull,
            fetchedUpdatedAt: remoteTasks.map(\.updatedAt)
        )
        if let watermark {
            try repository.setLastPullAt(watermark)
        }
    }

    private func backoffDate(for attempt: Int) -> Date {
        let seconds = min(pow(2.0, Double(attempt)) * 2.0, 300.0)
        return Date().addingTimeInterval(seconds)
    }

    private func publishSnapshot(
        isSyncing: Bool? = nil,
        lastSyncedAt: Date? = nil
    ) async {
        if let isSyncing {
            snapshot.isSyncing = isSyncing
        }
        if let lastSyncedAt {
            snapshot.lastSyncedAt = lastSyncedAt
        }
        snapshot.pendingCount = (try? repository.pendingSyncCount()) ?? snapshot.pendingCount
        snapshot.failedCount = (try? repository.failedSyncCount()) ?? snapshot.failedCount

        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }
}
