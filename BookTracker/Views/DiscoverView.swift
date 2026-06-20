import SwiftUI
import SwiftData

struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var savedBooks: [SavedBook]

    @State private var queryText = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let service = GoogleBooksService()

    private func isAlreadySaved(_ result: SearchResult) -> Bool {
        savedBooks.contains { $0.googleBooksID == result.id && !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { result in
                    HStack(spacing: 12) {
                        BookThumbnail(urlString: result.thumbnailURL)
                        VStack(alignment: .leading) {
                            Text(result.title).font(.headline)
                            Text(result.author).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isAlreadySaved(result) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Add") { addBook(result) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: queryText) { _, newValue in
                searchTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await performSearch()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                DiscoverHeader(queryText: $queryText, onDone: { dismiss() })
            }
            .overlay {
                if isSearching {
                    ProgressView("Searching…")
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else if results.isEmpty && !queryText.isEmpty {
                    ContentUnavailableView.search(text: queryText)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    private func performSearch() async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await service.search(query: queryText)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            results = []
        }
        isSearching = false
    }

    private func addBook(_ result: SearchResult) {
        // If this book was previously deleted (tombstoned), revive it rather
        // than inserting a duplicate with the same googleBooksID.
        if let existing = savedBooks.first(where: { $0.googleBooksID == result.id }) {
            existing.isArchived = false
            existing.title = result.title
            existing.author = result.author
            existing.publishedDate = result.publishedDate
            existing.summary = result.summary
            existing.thumbnailURL = result.thumbnailURL
            existing.updatedAt = .now
        } else {
            let book = SavedBook(
                googleBooksID: result.id,
                title: result.title,
                author: result.author,
                publishedDate: result.publishedDate,
                summary: result.summary,
                thumbnailURL: result.thumbnailURL
            )
            modelContext.insert(book)
        }
        try? modelContext.save()
        Task { await SyncService.shared.syncNow(context: modelContext) }
    }
}

struct DiscoverHeader: View {
    @Binding var queryText: String
    let onDone: () -> Void

    @AppStorage("appTheme") private var themeName: String = AppTheme.ocean.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeName) ?? .ocean }

    var body: some View {
        ZStack {
            theme.gradient.ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Button(action: onDone) {
                        Text("Done")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search by title or author", text: $queryText)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                .padding(10)
                .background(.white, in: Capsule())
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(height: 110)
    }
}
