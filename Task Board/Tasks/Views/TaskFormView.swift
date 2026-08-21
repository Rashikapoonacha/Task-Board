import SwiftUI

struct TaskFormView: View {
    @Bindable var viewModel: TaskFormViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Task title", text: $viewModel.title)
                }
                Section("Description") {
                    TextField("Description", text: $viewModel.description, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Subtasks") {
                    ForEach(viewModel.subtasks) { subtask in
                        HStack(spacing: 10) {
                            if viewModel.isEditing {
                                Button {
                                    viewModel.toggleSubtaskComplete(id: subtask.id)
                                } label: {
                                    Image(systemName: subtask.isComplete ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(subtask.isComplete ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            TextField(
                                "Subtask",
                                text: Binding(
                                    get: { subtask.title },
                                    set: { viewModel.updateSubtaskTitle(id: subtask.id, title: $0) }
                                )
                            )
                        }
                    }
                    .onDelete(perform: viewModel.removeSubtasks)

                    HStack {
                        TextField("New subtask", text: $viewModel.newSubtaskTitle)
                            .onSubmit { viewModel.addSubtask() }
                        Button("Add", action: viewModel.addSubtask)
                            .disabled(
                                viewModel.newSubtaskTitle
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                            )
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save()
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }
}
