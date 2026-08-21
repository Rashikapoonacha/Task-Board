import SwiftUI

struct BoardView: View {
    @Bindable var viewModel: BoardViewModel
    @State private var showingCreateForm = false
    @State private var editingTask: TaskItem?
    @State private var selectedStatus: TaskStatus = .todo

    private var visibleTasks: [TaskItem] {
        viewModel.tasksByStatus[selectedStatus] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SyncStatusBanner(snapshot: viewModel.syncSnapshot) {
                    viewModel.retrySync()
                }

                Picker("Status", selection: $selectedStatus) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                List {
                    if visibleTasks.isEmpty {
                        Text("No tasks")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(visibleTasks) { task in
                            TaskRowView(
                                task: task,
                                onEdit: { editingTask = task },
                                onMoveToStatus: { newStatus in
                                    let destinationCount = viewModel.tasksByStatus[newStatus]?.count ?? 0
                                    viewModel.moveTask(id: task.id, to: newStatus, at: destinationCount)
                                },
                                onArchive: {
                                    viewModel.archiveTask(id: task.id)
                                }
                            )
                            .swipeActions(edge: .leading) {
                                Button("Archive") {
                                    viewModel.archiveTask(id: task.id)
                                }
                                .tint(.indigo)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteTask(id: task.id)
                                }
                            }
                        }
                        .onMove(perform: moveTasks)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Task Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ArchiveView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "archivebox")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button {
                        showingCreateForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateForm) {
                TaskFormView(
                    viewModel: TaskFormViewModel { title, description in
                        viewModel.createTask(title: title, description: description)
                        showingCreateForm = false
                    }
                )
            }
            .sheet(item: $editingTask) { task in
                TaskFormView(
                    viewModel: TaskFormViewModel(task: task) { title, description in
                        viewModel.updateTask(id: task.id, title: title, description: description)
                        editingTask = nil
                    }
                )
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private func moveTasks(from source: IndexSet, to destination: Int) {
        var orderedIDs = visibleTasks.map(\.id)
        orderedIDs.move(fromOffsets: source, toOffset: destination)
        viewModel.reorderTasks(in: selectedStatus, orderedIDs: orderedIDs)
    }
}
