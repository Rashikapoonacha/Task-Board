import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let onEdit: () -> Void
    let onMoveToStatus: (TaskStatus) -> Void
    var onArchive: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            syncIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { status in
                    Button("Move to \(status.displayName)") {
                        onMoveToStatus(status)
                    }
                }
                if let onArchive {
                    Button("Archive") {
                        onArchive()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }

    @ViewBuilder
    private var syncIcon: some View {
        switch task.syncStatus {
        case .synced:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.body)
        case .pending:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .font(.body)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.body)
        }
    }
}
