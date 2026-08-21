import SwiftUI

struct ArchiveView: View {
    @Bindable var viewModel: BoardViewModel

    var body: some View {
        List {
            if viewModel.archivedTasks.isEmpty {
                Text("No archived tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.archivedTasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.leading)

                            if !task.taskDescription.isEmpty {
                                Text(task.taskDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Text(task.status.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Restore") {
                            viewModel.unarchiveTask(id: task.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
    }
}
