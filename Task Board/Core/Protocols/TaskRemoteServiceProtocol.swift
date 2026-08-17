import Foundation

protocol TaskRemoteServiceProtocol: Sendable {
    func fetchTasks(updatedSince: Date?) async throws -> [RemoteTaskDTO]
    func createTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult
    func updateTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult
    func deleteTask(_ task: RemoteTaskDTO, idempotencyKey: UUID) async throws -> RemoteMutationResult
}
