import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Bindable var book: SavedBook
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    BookThumbnail(urlString: book.thumbnailURL, width: 80, height: 112)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title)
                            .font(.title)
                            .bold()
                        Text(book.author)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(book.publishedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Status", selection: $book.status) {
                    ForEach(ReadingStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .tint(book.status.tint)
                .onChange(of: book.status) {
                    book.dateStatusChanged = .now
                    book.updatedAt = .now
                }

                StarRatingView(rating: $book.rating)
                    .font(.title3)
                    .onChange(of: book.rating) { book.updatedAt = .now }

                Divider()

                Text(book.summary.isEmpty ? "No summary available." : book.summary)
                    .font(.system(size: 17))
                    .lineSpacing(6)
                    .padding(8)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("My Notes")
                        .font(.headline)
                    TextEditor(text: $book.notes)
                        .font(.system(size: 17))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 1)
                        )
                        .onChange(of: book.notes) { book.updatedAt = .now }
                }
            }
            .padding(24)
        }
        .navigationTitle(book.title)
        .onDisappear {
            try? modelContext.save()
            Task { await SyncService.shared.syncNow(context: modelContext) }
        }
    }
}
