import Foundation
import Observation

@MainActor
@Observable
final class TaskFormViewModel {
    var title = ""
    var description = ""
    var isEditing = false

    private let taskId: UUID?
    private let onSave: (String, String) -> Void

    init(task: TaskItem? = nil, onSave: @escaping (String, String) -> Void) {
        self.taskId = task?.id
        self.onSave = onSave
        if let task {
            title = task.title
            description = task.taskDescription
            isEditing = true
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        guard canSave else { return }
        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
               description.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
