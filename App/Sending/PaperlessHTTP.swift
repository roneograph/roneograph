import Foundation

/// The requests to Paperless made while the app is open: checking the server, listing and creating document types.
enum PaperlessHTTP {
    /// Redirects are refused, so the token never goes to another address; the server must be typed as it answers.
    private static let session = URLSession(configuration: .ephemeral, delegate: RefusingRedirects(), delegateQueue: nil)

    @Sendable static func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

private final class RefusingRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
