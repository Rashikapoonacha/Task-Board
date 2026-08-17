import Foundation

enum SyncOperationKind: String, Sendable {
    case create
    case update
    case delete
}
