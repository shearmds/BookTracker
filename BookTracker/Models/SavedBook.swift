import Foundation
import SwiftData
import SwiftUI

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case wantToRead = "Want to Read"
    case inProgress = "In Progress"
    case read = "Read"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .wantToRead: .blue
        case .inProgress: .orange
        case .read: .green
        }
    }
}

@Model
final class SavedBook {
    var googleBooksID: String = ""
    var title: String = ""
    var author: String = ""
    var publishedDate: String = ""
    var summary: String = ""
    var thumbnailURL: String?
    var status: ReadingStatus = ReadingStatus.wantToRead
    var dateAdded: Date = Date.now
    var dateStatusChanged: Date = Date.now
    var notes: String = ""
    var rating: Int = 0

    // Sync metadata (Cloudflare Worker sync). `updatedAt` is bumped on every
    // mutation and drives last-write-wins merging. `isArchived` is a
    // tombstone: deletes are soft so they propagate across devices instead
    // of reappearing. Named isArchived rather than isDeleted: a property
    // literally named isDeleted does not survive modelContext.save() on this
    // SwiftData/CloudKit-schema-derived model — it silently reverts to false
    // on save with no thrown error (confirmed via direct fetch-after-save).
    // The wire format sent to the sync Worker still uses "isDeleted" as the
    // JSON key (see BookDTO below) so the server side didn't need changing.
    var updatedAt: Date = Date.now
    var isArchived: Bool = false

    init(
        googleBooksID: String,
        title: String,
        author: String,
        publishedDate: String,
        summary: String,
        thumbnailURL: String?,
        status: ReadingStatus = .wantToRead
    ) {
        self.googleBooksID = googleBooksID
        self.title = title
        self.author = author
        self.publishedDate = publishedDate
        self.summary = summary
        self.thumbnailURL = thumbnailURL
        self.status = status
        self.dateAdded = .now
        self.dateStatusChanged = .now
        self.notes = ""
        self.rating = 0
        self.updatedAt = .now
        self.isArchived = false
    }
}

// MARK: - Sync wire format

/// JSON shape exchanged with the sync Worker. Timestamps are epoch
/// milliseconds (Double) so the Worker can compare them numerically for
/// last-write-wins, matching the ReadLater sync pattern.
struct BookDTO: Codable {
    var googleBooksID: String
    var title: String
    var author: String
    var publishedDate: String
    var summary: String
    var thumbnailURL: String?
    var status: String
    var dateAdded: Double
    var dateStatusChanged: Double
    var notes: String
    var rating: Int
    var updatedAt: Double
    var isDeleted: Bool

    init(from book: SavedBook) {
        googleBooksID = book.googleBooksID
        title = book.title
        author = book.author
        publishedDate = book.publishedDate
        summary = book.summary
        thumbnailURL = book.thumbnailURL
        status = book.status.rawValue
        dateAdded = book.dateAdded.millis
        dateStatusChanged = book.dateStatusChanged.millis
        notes = book.notes
        rating = book.rating
        updatedAt = book.updatedAt.millis
        isDeleted = book.isArchived
    }

    /// Effective modification time, mirroring the Worker's merge logic.
    var effectiveTime: Double { max(updatedAt, dateStatusChanged, dateAdded) }

    /// Apply this DTO's fields onto a local book (used when the remote copy wins).
    func apply(to book: SavedBook) {
        book.title = title
        book.author = author
        book.publishedDate = publishedDate
        book.summary = summary
        book.thumbnailURL = thumbnailURL
        book.status = ReadingStatus(rawValue: status) ?? .wantToRead
        book.dateAdded = Date(millis: dateAdded)
        book.dateStatusChanged = Date(millis: dateStatusChanged)
        book.notes = notes
        book.rating = rating
        book.updatedAt = Date(millis: updatedAt)
        book.isArchived = isDeleted
    }

    /// Build a fresh SavedBook from a remote DTO (for books not present locally).
    func makeBook() -> SavedBook {
        let book = SavedBook(
            googleBooksID: googleBooksID,
            title: title,
            author: author,
            publishedDate: publishedDate,
            summary: summary,
            thumbnailURL: thumbnailURL,
            status: ReadingStatus(rawValue: status) ?? .wantToRead
        )
        book.dateAdded = Date(millis: dateAdded)
        book.dateStatusChanged = Date(millis: dateStatusChanged)
        book.notes = notes
        book.rating = rating
        book.updatedAt = Date(millis: updatedAt)
        book.isArchived = isDeleted
        return book
    }
}

struct SyncPayload: Codable {
    var books: [BookDTO]
}

extension Date {
    var millis: Double { timeIntervalSince1970 * 1000 }
    init(millis: Double) { self.init(timeIntervalSince1970: millis / 1000) }
}

extension SavedBook {
    /// The effective modification time used for last-write-wins comparisons.
    var effectiveTime: Date { max(updatedAt, dateStatusChanged, dateAdded) }
}
