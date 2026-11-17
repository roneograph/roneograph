import Foundation

/// The Paperless-ngx server an owner's scans are archived to; its token is kept in the Keychain, not here.
public struct PaperlessServer: Equatable, Sendable, Codable {
    /// The address of the server, ending with a slash, such as https://paperless.example.com/.
    public var url: URL
    /// Where Paperless files the owner's documents; nil lets Paperless decide.
    public var storagePath: PaperlessStoragePath?

    public init(url: URL, storagePath: PaperlessStoragePath? = nil) {
        self.url = url
        self.storagePath = storagePath
    }
}

public struct PaperlessStoragePath: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// The parts of the Paperless-ngx REST API Roneograph uses: listing storage paths and uploading a document.
public enum Paperless {
    /// Supported by Paperless-ngx 2.x and 3.x.
    static let accept = "application/json; version=9"

    /// The server address as typed, with https:// added when no scheme is given; nil when it is not an HTTPS address.
    public static func serverURL(from typed: String) -> URL? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return nil }
        components.query = nil
        components.fragment = nil
        if components.path.hasSuffix("/api/") { components.path.removeLast(4) }
        if components.path.hasSuffix("/api") { components.path.removeLast(3) }
        if !components.path.hasSuffix("/") { components.path += "/" }
        return components.url
    }

    public static func storagePathsRequest(server: URL, token: String) -> URLRequest {
        listRequest("api/storage_paths/", server: server, token: token)
    }

    public static func storagePaths(from data: Data) throws -> [PaperlessStoragePath] {
        try JSONDecoder().decode(Page<PaperlessStoragePath>.self, from: data).results
    }

    public static func documentTypesRequest(server: URL, token: String) -> URLRequest {
        listRequest("api/document_types/", server: server, token: token)
    }

    /// The IDs of the document types by their name, lowercased, as Paperless refuses two names that differ only by case.
    public static func documentTypes(from data: Data) throws -> [String: Int] {
        let types = try JSONDecoder().decode(Page<Named>.self, from: data).results
        return Dictionary(types.map { ($0.name.lowercased(), $0.id) }) { first, _ in first }
    }

    /// Creates a document type that Paperless never assigns by itself, so only the documents sent with it get it.
    public static func createDocumentTypeRequest(server: URL, token: String, name: String) -> URLRequest {
        var request = URLRequest(url: server.appending(path: "api/document_types/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name, "matching_algorithm": 0], options: .sortedKeys)
        authorize(&request, token: token)
        return request
    }

    public static func createdID(from data: Data) throws -> Int {
        try JSONDecoder().decode(Named.self, from: data).id
    }

    private struct Page<Result: Decodable>: Decodable {
        let results: [Result]
    }

    private struct Named: Decodable {
        let id: Int
        let name: String
    }

    private static func listRequest(_ path: String, server: URL, token: String) -> URLRequest {
        var request = URLRequest(url: server.appending(path: path).appending(queryItems: [
            URLQueryItem(name: "page_size", value: "1000"),
            URLQueryItem(name: "ordering", value: "name"),
        ]))
        authorize(&request, token: token)
        return request
    }

    /// The request for `uploadBody`, which is sent as a file.
    public static func uploadRequest(server: URL, token: String, boundary: String) -> URLRequest {
        var request = URLRequest(url: server.appending(path: "api/documents/post_document/"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        authorize(&request, token: token)
        return request
    }

    /// The form Paperless-ngx takes: the PDF with its file name, the title, the date of the document when known, the document type and the storage path.
    public static func uploadBody(pdf: Data, fileName: String, title: String, created: Date?, documentType: Int? = nil, storagePath: Int?, boundary: String, timeZone: TimeZone = .current) -> Data {
        var form = MultipartForm(boundary: boundary)
        form.add(name: "title", value: title)
        if let created {
            form.add(name: "created", value: created.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()))
        }
        if let documentType { form.add(name: "document_type", value: String(documentType)) }
        if let storagePath { form.add(name: "storage_path", value: String(storagePath)) }
        form.add(name: "document", fileName: fileName, contentType: "application/pdf", data: pdf)
        return form.finished()
    }

    private static func authorize(_ request: inout URLRequest, token: String) {
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
    }

    public enum Outcome: Equatable, Sendable {
        case delivered
        /// Worth trying again later; the reason is shown meanwhile.
        case retry(String)
        /// Trying again cannot help until something changes.
        case failed(String)
    }

    /// What an answer, or the lack of one, means for the document sent.
    public static func outcome(status: Int?, body: Data, error: URLError.Code?) -> Outcome {
        if let error {
            switch error {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
                return .failed("The server's certificate is not trusted.")
            case .unsupportedURL, .badURL:
                return .failed("The server address is not valid.")
            case .cannotFindHost, .dnsLookupFailed:
                return .retry("The server cannot be found.")
            default:
                return .retry("The server cannot be reached.")
            }
        }
        guard let status else { return .retry("The server cannot be reached.") }
        switch status {
        case 200..<300:
            return .delivered
        case 401, 403:
            return .failed("The server refused the token.")
        case 404:
            return .failed("The server is not a Paperless-ngx server, or its address is wrong.")
        case 413:
            return .failed("The server refused a file this large.")
        case 408, 429, 500...:
            return .retry("The server is not ready (error \(status)).")
        case 300..<400:
            return .failed("The server redirects to another address (error \(status)).")
        default:
            return .failed(errorMessage(in: body).map { "The server refused the document: \($0)" } ?? "The server refused the document (error \(status)).")
        }
    }

    /// The first message of a Django REST Framework error, such as {"document": ["The file is empty."]}.
    static func errorMessage(in body: Data) -> String? {
        func first(_ value: Any) -> String? {
            switch value {
            case let text as String: text
            case let list as [Any]: list.lazy.compactMap(first).first
            case let object as [String: Any]: object.keys.sorted().lazy.compactMap { object[$0].flatMap(first) }.first
            default: nil
            }
        }
        return (try? JSONSerialization.jsonObject(with: body)).flatMap(first)
    }
}

/// A multipart/form-data body (RFC 7578).
struct MultipartForm {
    let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func add(name: String, value: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func add(name: String, fileName: String, contentType: String, data file: Data) {
        let quoted = fileName.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing(/[\r\n]/, with: " ")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(quoted)\"\r\nContent-Type: \(contentType)\r\n\r\n")
        data.append(file)
        append("\r\n")
    }

    func finished() -> Data {
        var data = data
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    private mutating func append(_ text: String) {
        data.append(Data(text.utf8))
    }
}
