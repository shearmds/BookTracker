import SwiftUI
import SwiftData

@main
struct BookTrackerApp: App {
    @AppStorage("appTheme") private var themeName: String = AppTheme.ocean.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeName) ?? .ocean }

    @Environment(\.scenePhase) private var scenePhase

    // Plain local SwiftData store. Cross-device sync is handled by SyncService
    // (Cloudflare Worker), not CloudKit.
    private let container: ModelContainer = Self.makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([SavedBook.self])
        let configuration = ModelConfiguration(schema: schema)

        // First attempt: open the on-disk store normally.
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        // Recovery: the store is unreadable (corruption or an unsupported
        // migration). Rather than crash-loop on every launch, delete the store
        // files and start fresh — the library re-populates from the sync Worker.
        if let storeURL = configuration.url as URL? {
            for url in [storeURL,
                        storeURL.appendingPathExtension("wal"),
                        storeURL.appendingPathExtension("shm")] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        // Last resort: an in-memory store so the app still launches.
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memoryConfig])
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .tint(theme.end)
                .task {
                    await SyncService.shared.syncNow(context: container.mainContext)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await SyncService.shared.syncNow(context: container.mainContext) }
            }
        }
    }
}
