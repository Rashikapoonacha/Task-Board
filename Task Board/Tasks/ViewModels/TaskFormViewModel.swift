import Foundation
import Observation

@MainActor
@Observable
final class TaskFormViewModel {
    var title = ""
    var description = ""
    var subtasks: [SubtaskItem] = []
    var newSubtaskTitle = ""
    var isEditing = false

    private let onSave: (String, String, [SubtaskItem]) -> Void

    init(task: TaskItem? = nil, onSave: @escaping (String, String, [SubtaskItem]) -> Void) {
        self.onSave = onSave
        if let task {
            title = task.title
            description = task.taskDescription
            subtasks = task.subtasks
            isEditing = true
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtasks.append(
            SubtaskItem(id: UUID(), title: trimmed, isComplete: false, sortOrder: subtasks.count)
        )
        newSubtaskTitle = ""
    }

    func removeSubtasks(at offsets: IndexSet) {
        subtasks = subtasks.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        renumberSubtasks()
    }

    func updateSubtaskTitle(id: UUID, title: String) {
        guard let index = subtasks.firstIndex(where: { $0.id == id }) else { return }
        subtasks[index].title = title
    }

    func toggleSubtaskComplete(id: UUID) {
        guard let index = subtasks.firstIndex(where: { $0.id == id }) else { return }
        subtasks[index].isComplete.toggle()
    }

    func save() {
        guard canSave else { return }
        onSave(
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            description.trimmingCharacters(in: .whitespacesAndNewlines),
            renumberedSubtasks()
        )
    }

    private func renumberSubtasks() {
        subtasks = subtasks.enumerated().map { index, item in
            SubtaskItem(id: item.id, title: item.title, isComplete: item.isComplete, sortOrder: index)
        }
    }

    private func renumberedSubtasks() -> [SubtaskItem] {
        subtasks.enumerated().map { index, item in
            SubtaskItem(
                id: item.id,
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                isComplete: item.isComplete,
                sortOrder: index
            )
        }
        .filter { !$0.title.isEmpty }
    }
}
