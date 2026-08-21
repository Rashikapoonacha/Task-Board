import FirebaseFirestore
import Foundation

nonisolated final class FirestoreTaskService: TaskRemoteServiceProtocol, @unchecked Sendable {
    private let collectionName = "tasks"

    func fetchTasks(updatedSince: Date?) async throws -> [RemoteTaskDTO] {
        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [collectionName] in
                let db = Firestore.firestore()
                var query: Query = db.collection(collectionName)
                if let updatedSince {
                    query = query.whereField("updatedAt", isGreaterThan: Timestamp(date: updatedSince))
                }
                query.getDocuments { snapshot, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let snapshot {
                        continuation.resume(returning: snapshot)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirestoreTaskService", code: -1))
                    }
                }
            }
        }
        return snapshot.documents.compactMap { mapData($0.data()) }
    }

    func createTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult {
        try await mutate(documentID: task.id.uuidString) { existing in
            RemoteConcurrency.create(existing: existing, incoming: task)
        } write: { incoming in
            self.documentData(for: incoming, idempotencyKey: idempotencyKey)
        }
    }

    func updateTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult {
        try await mutate(documentID: task.id.uuidString) { existing in
            RemoteConcurrency.update(existing: existing, incoming: task)
        } write: { incoming in
            self.documentData(for: incoming, idempotencyKey: idempotencyKey)
        }
    }

    func deleteTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult {
        try await mutate(documentID: task.id.uuidString) { existing in
            RemoteConcurrency.delete(existing: existing, incoming: task)
        } write: { incoming in
            [
                "deleted": true,
                "updatedAt": Timestamp(date: incoming.updatedAt),
                "idempotencyKey": idempotencyKey.uuidString
            ]
        }
    }

    // MARK: - Private

    private func mutate(
        documentID: String,
        decide: @escaping (RemoteTaskDTO?) -> RemoteMutationResult,
        write: @escaping (RemoteTaskDTO) -> [String: Any]
    ) async throws -> RemoteMutationResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RemoteMutationResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [collectionName] in
                let db = Firestore.firestore()
                let ref = db.collection(collectionName).document(documentID)
                var outcome: RemoteMutationResult?

                db.runTransaction({ transaction, errorPointer in
                    let snapshot: DocumentSnapshot
                    do {
                        snapshot = try transaction.getDocument(ref)
                    } catch let error as NSError {
                        errorPointer?.pointee = error
                        return nil
                    }

                    let existing = snapshot.exists ? self.mapData(snapshot.data() ?? [:]) : nil
                    let decision = decide(existing)
                    outcome = decision
                    if case .success(let incoming) = decision {
                        transaction.setData(write(incoming), forDocument: ref, merge: true)
                    }
                    return nil
                }, completion: { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let outcome {
                        continuation.resume(returning: outcome)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirestoreTaskService", code: -2))
                    }
                })
            }
        }
    }

    private func documentData(for task: RemoteTaskDTO, idempotencyKey: UUID) -> [String: Any] {
        [
            "id": task.id.uuidString,
            "title": task.title,
            "description": task.description,
            "status": task.status.rawValue,
            "sortOrder": task.sortOrder,
            "createdAt": Timestamp(date: task.createdAt),
            "updatedAt": Timestamp(date: task.updatedAt),
            "deleted": task.isDeleted,
            "archived": task.isArchived,
            "subtasks": RemoteTaskMapping.subtasksPayload(task.subtasks),
            "idempotencyKey": idempotencyKey.uuidString
        ]
    }

    private func mapData(_ data: [String: Any]) -> RemoteTaskDTO? {
        RemoteTaskMapping.makeDTO(from: data) { value in
            (value as? Timestamp)?.dateValue()
        }
    }
}
