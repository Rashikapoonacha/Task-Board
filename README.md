# Offline-First Task Board

## Overview

An iOS SwiftUI app for organizing tasks across **To Do**, **In Progress**, and **Done**. Users create, edit, delete, move, and reorder tasks. The UI is a segmented control with one list at a time.

**Core Data is the local source of truth.** Mutations apply locally first, so create/edit/delete/move/reorder work immediately while offline. Firebase Firestore is used only for later synchronization. A banner and per-row icons show offline, syncing, pending, and failed state.

## Architecture

SwiftUI views and MVVM ViewModels talk only to `TaskRepository`. The repository writes **Core Data** and enqueues a durable **OutboxStore** row. `SyncEngine` (an actor) is the sole remote orchestrator: it pushes the outbox, then pulls remote changes through `TaskRemoteServiceProtocol`, implemented by `FirestoreTaskService`. `ConflictResolver` runs during pull. `NetworkMonitor` reports connectivity and triggers sync when the device comes online. The UI never calls Firestore.

## Important Technical Decisions

| Decision | Why |
|----------|-----|
| Core Data as source of truth | The board can always render and mutate local state without waiting on the network. |
| Durable outbox (`OutboxStore`) | Pending create/update/delete operations survive app termination until they sync. |
| `SyncEngine` owns synchronization | Views stay free of Firebase; one actor sequences push, pull, and retry. |
| Push before pull | This device’s pending mutations are attempted before applying other devices’ updates. |
| `TaskRemoteServiceProtocol` | Firestore stays behind one boundary so tests can use a mock remote. |
| `updatedAt`-based conflict resolution | Simple last-write-wins is enough for this take-home; CRDTs and version vectors were out of scope. |
| Protect stale offline writes / no resurrection | A stale push must not overwrite a newer remote edit or restore a remotely deleted task. |
| MVVM | Views stay presentation-only; repository and sync own data and networking. |

## Synchronization & Conflict Resolution

A user action writes Core Data (`syncStatus = pending`, client `updatedAt` bumped), updates the UI immediately, and persists an outbox operation. When online, `SyncEngine` pushes ready outbox items, then pulls remote tasks. Pull never overwrites a local task that is `pending`, `failed`, or still in the outbox. Deletes are tombstones (`tombstoned` locally, `deleted` on Firestore).

On **pull**, a synced task is replaced only if remote `updatedAt` is greater than this device’s `remoteUpdatedAt` (the last remote timestamp observed after a successful push or pull; if that is missing, local `updatedAt` is used). On **push**, the write is skipped if the remote document’s `updatedAt` is greater than this device’s `remoteUpdatedAt`; the outbox row is dropped and the remote snapshot is applied. That is how a stale offline edit loses to a newer remote edit and does not resurrect a remotely deleted task.

Incremental pull requests documents with `updatedAt` greater than `lastPullAt`. `lastPullAt` is the maximum remote `updatedAt` actually fetched, not device `Date()`. An empty fetch leaves the previous watermark so offline-created tasks with older client timestamps are not skipped forever.

This is intentionally simpler than production CRDTs or version vectors. `updatedAt` is client-generated.

**Two-device (manually tested: simulator + physical device):**

1. A edits offline. B edits the same task online and syncs. A reconnects and syncs. B’s newer remote version is kept; A’s stale edit is not applied. If A was already in the foreground, relaunch is required for the updated remote state to appear in the UI.
2. A deletes online. B edits a stale copy offline. B reconnects. The deletion remains; the task is not resurrected.

## Offline & Persistence

Create, edit, delete, move, and reorder work without connectivity and update the UI immediately. Task rows and outbox rows are stored in Core Data, so they remain after kill and relaunch. When connectivity returns, `NetworkMonitor` and `SyncEngine` push pending work and pull remote changes. There is no background refresh and no Firestore realtime listener.

## Testing

### Automated

Swift Testing with in-memory Core Data and a mock remote:

- **ConflictResolver** — pending/failed/outbox keep local; synced last-write-wins
- **OutboxStore** — enqueue, coalesce, backoff
- **TaskRepository** — create, tombstone delete, reorder, immediate edit observation
- **SyncEngine** — push-then-pull, pull skips pending local, retry after `resetRetryState`, incremental pull watermark, newer remote edit vs stale offline edit, remote delete vs stale offline edit, stale delete vs newer remote edit, offline create still syncs
- **RemoteConcurrency / mapping** — create/update/delete conflict rules; `sortOrder` Int64/NSNumber decoding


### Manual

- Offline create, edit, delete
- Offline move and reorder
- Kill/relaunch while offline (tasks and outbox survive)
- Reconnect and sync
- Two-device concurrent edit
- Online delete vs stale offline edit (no resurrection)

Template UITests are not product coverage.

## Known Limitations

- Client `updatedAt` can be wrong if device clocks differ.
- No authentication; one shared `tasks` collection.
- No realtime listeners, background sync, or foreground refresh of remote changes.
- No conflict-choice UI; resolution is deterministic.

## Features I Would Add With More Time

Not implemented:

1. Server-authoritative timestamps or versions
2. Authentication and per-user data
3. Firestore realtime listeners
4. Background sync
5. A conflict/resolution UI
6. Broader UI and integration tests

## Assumptions

- The included `GoogleService-Info.plist` and a Firestore database are used for review.
- One flat `tasks` collection; document ID is the client task UUID.
- The assignment does not require authentication.
- Device clocks are close enough for `updatedAt` last-write-wins.
- Core Data is authoritative for immediate UX; Firestore is sync only.
- Task counts stay small (`Int` sort order, column renumber on reorder).

## Approximate Time Spent

About **7-8 hours**, matching the assignment’s expected effort.

## AI Usage

Cursor was used for architecture planning, scaffolding, debugging, test planning, and review. I identified the core flows and edge cases, directed the implementation and test scenarios, and manually verified the resulting behavior, including offline persistence and two-device conflict cases. AI did not independently validate the product.


## How to Run

1. Open `Task Board.xcodeproj` in Xcode 16+ (app target iOS 17.6+).
2. Confirm `Task Board/GoogleService-Info.plist` is in the app target.
3. Enable Firestore. Development rules (open; not for production):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /tasks/{taskId} {
      allow read, write: if true;
    }
  }
}
```

4. Run the **Task Board** scheme.
5. Offline: Airplane Mode, mutate tasks (UI should update immediately), then reconnect. Two-device tests: same Firebase project on two clients. Remote changes from another device are not reflected in an already-running foreground app until the app is relaunched.
