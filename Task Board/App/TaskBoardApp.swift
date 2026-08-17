import SwiftUI
import FirebaseCore

@main
struct TaskBoardApp: App {
    private let onlineStatus: OnlineStatusBox
    private let networkMonitor: NetworkMonitor
    private let boardViewModel: BoardViewModel
    private let syncEngine: SyncEngine

    init() {
        FirebaseApp.configure()

        let onlineStatus = OnlineStatusBox()
        let networkMonitor = NetworkMonitor()
        let persistence = PersistenceController.shared
        let outbox = OutboxStore { persistence.writeContext }
        let repository = TaskRepository(persistence: persistence, outbox: outbox)
        let syncEngine = SyncEngine(
            repository: repository,
            outbox: outbox,
            remote: FirestoreTaskService(),
            isOnline: { onlineStatus.isOnline }
        )

        repository.setOnMutation {
            Task.detached { await syncEngine.requestSync() }
        }

        networkMonitor.onStatusChange = { isOnline in
            onlineStatus.isOnline = isOnline
            Task.detached { await syncEngine.setOnline(isOnline) }
        }

        self.onlineStatus = onlineStatus
        self.networkMonitor = networkMonitor
        self.syncEngine = syncEngine
        self.boardViewModel = BoardViewModel(repository: repository, syncEngine: syncEngine, outbox: outbox)
    }

    var body: some Scene {
        WindowGroup {
            BoardView(viewModel: boardViewModel)
                .onAppear {
                    onlineStatus.isOnline = networkMonitor.isOnline
                    Task.detached { await syncEngine.requestSync() }
                }
        }
    }
}
