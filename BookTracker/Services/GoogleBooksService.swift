import Foundation

enum GoogleBooksError: Error {
    case invalidQuery
    case requestFailed
}

struct GoogleBooksService {
    // Searches go through the sync Worker, which holds the Google Books API key
    // server-side (so it isn't shipped in the public app binary) and proxies
    // the request, returning Google's response JSON unchanged.
    private let searchURL = "https://booktracker-sync.shearm.workers.dev/search"

    func search(query: String, retriesRemaining: Int = 2) async throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw GoogleBooksError.invalidQuery
        }

        let urlString = "\(searchURL)?q=\(encodedQuery)"
        guard let url = URL(string: urlString) else {
            throw GoogleBooksError.invalidQuery
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("Book search HTTP \(statusCode): \(body)")

            if statusCode >= 500, retriesRemaining > 0 {
                try await Task.sleep(for: .seconds(1.5))
                return try await search(query: query, retriesRemaining: retriesRemaining - 1)
            }
            throw GoogleBooksError.requestFailed
        }

        let decoded = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
        return (decoded.items ?? []).map(\.asSearchResult)
    }
}
