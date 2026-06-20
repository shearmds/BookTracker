import Foundation
import SwiftData
import Observation

/// Syncs the local SwiftData library with the Cloudflare Worker.
///
/// Mirrors the ReadLater pattern: a per-user sync token (generated on first
/// launch, pasteable onto other devices to link them) is sent as a Bearer
/// token. The Worker keys storage by that token, so each token is its own
/// private library. `POST /sync` pushes local books, the Worker merges them
/// with what it has (last-write-wins, deduped by googleBooksID) and returns
/// the merged set, which we reconcile back into SwiftData.
@Observable
final class SyncService {
    static let shared = SyncService()

    private let syncURL = URL(string: "https://booktracker-sync.shearm.workers.dev/sync")!
    private let tokenKey = "bookSyncToken"

    private(set) var isSyncing = false
    var lastError: String?

    private init() {}

    // MARK: - Token

    /// Per-user sync key. Generated on first access; paste an existing key
    /// (in Settings) to link this device to your other devices.
    var token: String {
        get {
            if let existing = UserDefaults.standard.string(forKey: tokenKey),
               existing.count >= 32 {
                return existing
            }
            let generated = Self.generateToken()
            UserDefaults.standard.set(generated, forKey: tokenKey)
            return generated
        }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            UserDefaults.standard.set(cleaned, forKey: tokenKey)
        }
    }

    static func generateToken() -> String {
        (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    // MARK: - Sync

    @MainActor
    func syncNow(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        // Gather every local book, including tombstoned ones, so deletes propagate.
        let locals: [SavedBook]
        do {
            locals = try context.fetch(FetchDescriptor<SavedBook>())
        } catch {
            lastError = "Couldn't read local library."
            return
        }

        let payload = SyncPayload(books: locals.map(BookDTO.init(from:)))
        guard let body = try? JSONEncoder().encode(payload) else {
            lastError = "Couldn't encode library."
            return
        }

        var request = URLRequest(url: syncURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = "Sync failed (server error)."
                return
            }
            let merged = try JSONDecoder().decode(SyncPayload.self, from: data)
            reconcile(remote: merged.books, locals: locals, context: context)
        } catch {
            lastError = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Apply the Worker's merged result to the local store. The response is the
    /// authoritative merge of what we sent plus what was already stored, so we
    /// upsert each returned book when it's newer than the local copy.
    @MainActor
    private func reconcile(remote: [BookDTO], locals: [SavedBook], context: ModelContext) {
        var byID: [String: SavedBook] = [:]
        for book in locals { byID[book.googleBooksID] = book }

        for dto in remote {
            if let local = byID[dto.googleBooksID] {
                if dto.effectiveTime > local.effectiveTime.millis {
                    dto.apply(to: local)
                }
            } else {
                context.insert(dto.makeBook())
            }
        }

        try? context.save()
    }
}
