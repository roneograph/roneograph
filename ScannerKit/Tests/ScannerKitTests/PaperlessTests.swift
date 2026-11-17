import Foundation
import ScannerKit
import Testing

struct PaperlessTests {
    @Test(arguments: [
        ("paperless.example.ts.net", "https://paperless.example.ts.net/"),
        ("https://paperless.example.ts.net", "https://paperless.example.ts.net/"),
        (" https://example.com:8443/paperless/api/ ", "https://example.com:8443/paperless/"),
        ("https://example.com/api?x=1#top", "https://example.com/"),
    ])
    func readsTheServerAddress(typed: String, url: String) {
        #expect(Paperless.serverURL(from: typed)?.absoluteString == url)
    }

    @Test(arguments: ["", "http://paperless.local", "ftp://example.com", "https://user:secret@example.com", "https://"])
    func refusesAnAddressThatIsNotHTTPS(typed: String) {
        #expect(Paperless.serverURL(from: typed) == nil)
    }

    @Test func listsStoragePathsWithTheToken() throws {
        let request = Paperless.storagePathsRequest(server: URL(string: "https://example.com/paperless/")!, token: "abc")
        #expect(request.url?.absoluteString == "https://example.com/paperless/api/storage_paths/?page_size=1000&ordering=name")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token abc")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json; version=9")
    }

    @Test func readsStoragePaths() throws {
        let json = #"{"count": 2, "next": null, "results": [{"id": 3, "name": "Holding", "path": "holding/{{ title }}"}, {"id": 1, "name": "Personal"}]}"#
        #expect(try Paperless.storagePaths(from: Data(json.utf8)) == [PaperlessStoragePath(id: 3, name: "Holding"), PaperlessStoragePath(id: 1, name: "Personal")])
    }

    @Test func postsTheDocumentAsAForm() {
        let request = Paperless.uploadRequest(server: URL(string: "https://example.com/")!, token: "abc", boundary: "XYZ")
        #expect(request.url?.absoluteString == "https://example.com/api/documents/post_document/")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=XYZ")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token abc")
    }

    @Test func sendsThePDFWithItsTitleDateAndStoragePath() throws {
        let date = try Date("2026-03-01T23:30:00Z", strategy: .iso8601)
        let body = Paperless.uploadBody(pdf: Data("%PDF-1.7".utf8), fileName: "2026-03 \"Lumen\" invoice.pdf", title: "Lumen invoice", created: date, storagePath: 3, boundary: "XYZ", timeZone: TimeZone(identifier: "Europe/Paris")!)
        #expect(String(decoding: body, as: UTF8.self) == """
            --XYZ\r
            Content-Disposition: form-data; name="title"\r
            \r
            Lumen invoice\r
            --XYZ\r
            Content-Disposition: form-data; name="created"\r
            \r
            2026-03-02\r
            --XYZ\r
            Content-Disposition: form-data; name="storage_path"\r
            \r
            3\r
            --XYZ\r
            Content-Disposition: form-data; name="document"; filename="2026-03 \\"Lumen\\" invoice.pdf"\r
            Content-Type: application/pdf\r
            \r
            %PDF-1.7\r
            --XYZ--\r

            """)
    }

    @Test func leavesOutTheDateAndStoragePathWhenThereIsNone() {
        let body = String(decoding: Paperless.uploadBody(pdf: Data(), fileName: "a.pdf", title: "A", created: nil, storagePath: nil, boundary: "XYZ"), as: UTF8.self)
        #expect(!body.contains("created"))
        #expect(!body.contains("storage_path"))
    }

    @Test(arguments: [
        (200, Paperless.Outcome.delivered),
        (401, .failed("The server refused the token.")),
        (403, .failed("The server refused the token.")),
        (404, .failed("The server is not a Paperless-ngx server, or its address is wrong.")),
        (408, .retry("The server is not ready (error 408).")),
        (429, .retry("The server is not ready (error 429).")),
        (503, .retry("The server is not ready (error 503).")),
        (302, .failed("The server redirects to another address (error 302).")),
        (400, .failed("The server refused the document (error 400).")),
    ])
    func tellsWhatAnAnswerMeans(status: Int, outcome: Paperless.Outcome) {
        #expect(Paperless.outcome(status: status, body: Data(), error: nil) == outcome)
    }

    @Test func quotesTheReasonTheServerGives() {
        let body = Data(#"{"document": ["The submitted file is empty."]}"#.utf8)
        #expect(Paperless.outcome(status: 400, body: body, error: nil) == .failed("The server refused the document: The submitted file is empty."))
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, Paperless.Outcome.retry("The server cannot be reached.")),
        (.timedOut, .retry("The server cannot be reached.")),
        (.cannotFindHost, .retry("The server cannot be found.")),
        (.serverCertificateUntrusted, .failed("The server's certificate is not trusted.")),
    ])
    func tellsWhatANetworkErrorMeans(error: URLError.Code, outcome: Paperless.Outcome) {
        #expect(Paperless.outcome(status: nil, body: Data(), error: error) == outcome)
    }
}
