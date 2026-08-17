import SwiftUI

struct SyncStatusBanner: View {
    let snapshot: SyncSnapshot
    let onRetry: () -> Void

    var body: some View {
        if let message = bannerMessage {
            HStack {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(foregroundColor)
                Spacer()
                if snapshot.failedCount > 0 {
                    Button("Retry", action: onRetry)
                        .font(.caption.weight(.semibold))
                } else if snapshot.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
        }
    }

    private var bannerMessage: String? {
        if !snapshot.isOnline {
            return "Offline — changes saved locally"
        }
        if snapshot.failedCount > 0 {
            return "\(snapshot.failedCount) task(s) failed to sync"
        }
        if snapshot.isSyncing {
            return "Syncing…"
        }
        if snapshot.pendingCount > 0 {
            return "\(snapshot.pendingCount) change(s) pending sync"
        }
        return nil
    }

    private var backgroundColor: Color {
        if !snapshot.isOnline { return Color.orange.opacity(0.15) }
        if snapshot.failedCount > 0 { return Color.red.opacity(0.15) }
        if snapshot.pendingCount > 0 || snapshot.isSyncing { return Color.blue.opacity(0.12) }
        return Color.clear
    }

    private var foregroundColor: Color {
        if snapshot.failedCount > 0 { return .red }
        if !snapshot.isOnline { return .orange }
        return .secondary
    }
}
