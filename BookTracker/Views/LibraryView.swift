import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(filter: #Predicate<SavedBook> { !$0.isArchived }, sort: \SavedBook.title)
    private var books: [SavedBook]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var statusFilter: ReadingStatus?
    @State private var minRatingFilter: Int?
    @State private var showingAddBook = false
    @State private var showingSettings = false

    private var filteredBooks: [SavedBook] {
        books.filter { book in
            let matchesStatus = statusFilter == nil || book.status == statusFilter
            let matchesRating = minRatingFilter == nil || book.rating >= minRatingFilter!
            let matchesSearch = searchText.isEmpty
                || book.title.localizedCaseInsensitiveContains(searchText)
                || book.author.localizedCaseInsensitiveContains(searchText)
            return matchesStatus && matchesRating && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredBooks) { book in
                    NavigationLink(value: book) {
                        BookRowView(book: book)
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .refreshable {
                await SyncService.shared.syncNow(context: modelContext)
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: SavedBook.self) { book in
                BookDetailView(book: book)
            }
            .searchable(text: $searchText, prompt: "Search your books")
            .safeAreaInset(edge: .top, spacing: 0) {
                LibraryHeader(
                    bookCount: filteredBooks.count,
                    statusFilter: $statusFilter,
                    minRatingFilter: $minRatingFilter,
                    onAddBook: { showingAddBook = true },
                    onShowSettings: { showingSettings = true },
                    onSync: { Task { await SyncService.shared.syncNow(context: modelContext) } }
                )
            }
            .sheet(isPresented: $showingAddBook) {
                DiscoverView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        // Soft delete: tombstone the book so the deletion syncs to other
        // devices instead of the book reappearing on the next merge.
        for index in offsets {
            let book = filteredBooks[index]
            book.isArchived = true
            book.updatedAt = .now
        }
        try? modelContext.save()
        Task { await SyncService.shared.syncNow(context: modelContext) }
    }
}

struct LibraryHeader: View {
    let bookCount: Int
    @Binding var statusFilter: ReadingStatus?
    @Binding var minRatingFilter: Int?
    let onAddBook: () -> Void
    let onShowSettings: () -> Void
    let onSync: () -> Void

    @AppStorage("appTheme") private var themeName: String = AppTheme.ocean.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeName) ?? .ocean }

    var body: some View {
        ZStack {
            theme.gradient.ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                    Text("My Library")
                        #if os(iOS)
                        .font(.title2.bold())
                        #else
                        .font(.largeTitle.bold())
                        #endif
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Text("\(bookCount) \(bookCount == 1 ? "book" : "books")")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                        .fixedSize()

                    HStack(spacing: 16) {
                        if SyncService.shared.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .frame(width: 18, height: 18)
                        } else {
                            Button(action: onSync) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: onAddBook) {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        Button(action: onShowSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 10) {
                    Menu {
                        Button("All") { statusFilter = nil }
                        ForEach(ReadingStatus.allCases) { status in
                            Button(status.rawValue) { statusFilter = status }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Status: \(statusFilter?.rawValue ?? "All")")
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.25))
                        .clipShape(Capsule())
                    }
                    Menu {
                        Button("All") { minRatingFilter = nil }
                        ForEach((1...5).reversed(), id: \.self) { stars in
                            Button("\(stars)+ ★") { minRatingFilter = stars }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Rating: \(minRatingFilter.map { "\($0)+ ★" } ?? "All")")
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.25))
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
                .font(.footnote.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal)
                .tint(.white)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(height: 130)
    }
}

struct BookRowView: View {
    let book: SavedBook

    var body: some View {
        HStack(spacing: 12) {
            BookThumbnail(urlString: book.thumbnailURL)
            VStack(alignment: .leading) {
                Text(book.title).font(.headline)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                if book.rating > 0 {
                    Text(String(repeating: "★", count: book.rating))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(book.status.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(book.status.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(book.status.tint.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

struct BookThumbnail: View {
    let urlString: String?
    var width: CGFloat = 40
    var height: CGFloat = 56

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .overlay(Image(systemName: "book.closed").foregroundStyle(.secondary))
    }
}
