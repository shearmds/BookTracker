import Foundation

struct SearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let publishedDate: String
    let summary: String
    let thumbnailURL: String?
}

// MARK: - Google Books API decoding

struct GoogleBooksResponse: Decodable {
    let items: [VolumeItem]?
}

struct VolumeItem: Decodable {
    let id: String
    let volumeInfo: VolumeInfo
}

struct VolumeInfo: Decodable {
    let title: String?
    let authors: [String]?
    let publishedDate: String?
    let description: String?
    let imageLinks: ImageLinks?
}

struct ImageLinks: Decodable {
    let thumbnail: String?
}

extension VolumeItem {
    var asSearchResult: SearchResult {
        SearchResult(
            id: id,
            title: volumeInfo.title ?? "Untitled",
            author: volumeInfo.authors?.joined(separator: ", ") ?? "Unknown Author",
            publishedDate: volumeInfo.publishedDate ?? "",
            summary: volumeInfo.description ?? "",
            thumbnailURL: volumeInfo.imageLinks?.thumbnail?.replacingOccurrences(of: "http://", with: "https://")
        )
    }
}
