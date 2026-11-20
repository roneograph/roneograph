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

    @Test(arguments: [(PaperlessObjectKind.documentType, "document_types"), (.correspondent, "correspondents")])
    func listsTheObjectsByName(kind: PaperlessObjectKind, path: String) throws {
        let request = Paperless.listRequest(of: kind, server: URL(string: "https://example.com/paperless/")!, token: "abc")
        #expect(request.url?.absoluteString == "https://example.com/paperless/api/\(path)/?page_size=1000&ordering=name")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token abc")
    }

    @Test func readsTheObjectsOfAPageAndTheNextOne() throws {
        let json = #"{"count": 3, "next": "https://example.com/api/correspondents/?ordering=name&page=2&page_size=1000", "results": [{"id": 4, "name": "Lumen Energy", "matching_algorithm": 6}, {"id": 2, "name": "ACME"}]}"#
        let page = try Paperless.objects(from: Data(json.utf8))
        #expect(page.objects == [PaperlessObject(id: 4, name: "Lumen Energy"), PaperlessObject(id: 2, name: "ACME")])
        #expect(page.next?.absoluteString == "https://example.com/api/correspondents/?ordering=name&page=2&page_size=1000")
        #expect(try Paperless.objects(from: Data(#"{"next": null, "results": []}"#.utf8)).next == nil)
    }

    @Test func asksForTheNextPageAtTheAddressOfTheFirstOne() throws {
        let first = Paperless.listRequest(of: .correspondent, server: URL(string: "https://example.com/paperless/")!, token: "abc")
        let next = try #require(Paperless.nextPageRequest(after: first, next: URL(string: "http://internal:8000/api/correspondents/?ordering=name&page=3&page_size=1000")!))
        #expect(next.url?.absoluteString == "https://example.com/paperless/api/correspondents/?page_size=1000&ordering=name&page=3")
        #expect(next.value(forHTTPHeaderField: "Authorization") == "Token abc")
        #expect(Paperless.nextPageRequest(after: first, next: URL(string: "https://example.com/api/correspondents/")!) == nil)
    }

    @Test(arguments: [(PaperlessObjectKind.documentType, "document_types", "Payslip"), (.correspondent, "correspondents", "Lumen Energy")])
    func createsAnObjectWithAutoMatching(kind: PaperlessObjectKind, path: String, name: String) throws {
        let request = Paperless.createRequest(of: kind, server: URL(string: "https://example.com/")!, token: "abc", name: name)
        #expect(request.url?.absoluteString == "https://example.com/api/\(path)/")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token abc")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"matching_algorithm":6,"name":"\#(name)"}"#)
        #expect(try Paperless.createdObject(from: Data(#"{"id": 9, "name": "\#(name)", "slug": "x"}"#.utf8)) == PaperlessObject(id: 9, name: name))
    }

    @Test func sendsTheCorrespondent() {
        let body = String(decoding: Paperless.uploadBody(pdf: Data(), fileName: "a.pdf", title: "A", created: nil, correspondent: 4, storagePath: nil, boundary: "XYZ"), as: UTF8.self)
        #expect(body.contains("--XYZ\r\nContent-Disposition: form-data; name=\"correspondent\"\r\n\r\n4\r\n"))
    }

    @Test func listsCustomFieldsByTheirExactName() throws {
        let request = Paperless.customFieldsRequest(server: URL(string: "https://example.com/")!, token: "abc")
        #expect(request.url?.absoluteString == "https://example.com/api/custom_fields/?page_size=1000&ordering=name")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token abc")
        let json = #"{"results": [{"id": 5, "name": "Owner", "data_type": "string"}, {"id": 6, "name": "owner", "data_type": "select"}, {"id": 7, "name": "Notes", "data_type": "longtext"}]}"#
        #expect(try Paperless.customFields(from: Data(json.utf8)) == [
            "Owner": Paperless.TextField(id: 5, maximumLength: 128),
            "owner": Optional<Paperless.TextField>.none,
            "Notes": Paperless.TextField(id: 7, maximumLength: nil),
        ])
    }

    @Test func createsAStringCustomField() {
        let request = Paperless.createTextFieldRequest(server: URL(string: "https://example.com/")!, token: "abc", name: "Owner")
        #expect(request.url?.absoluteString == "https://example.com/api/custom_fields/")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token abc")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"data_type":"string","name":"Owner"}"#)
    }

    @Test func createsALongTextCustomField() throws {
        let request = Paperless.createTextFieldRequest(server: URL(string: "https://example.com/")!, token: "abc", name: "Comment", isLong: true)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"data_type":"longtext","name":"Comment"}"#)
        #expect(try Paperless.createdTextField(from: Data(#"{"id": 8, "name": "Comment", "data_type": "longtext"}"#.utf8)) == Paperless.TextField(id: 8, maximumLength: nil))
        #expect(throws: DecodingError.self) { try Paperless.createdTextField(from: Data(#"{"id": 8, "name": "Comment", "data_type": "select"}"#.utf8)) }
    }

    @Test(arguments: [
        ("2.19.0", true),
        ("2.20.13", true),
        ("3.5.0", true),
        ("10.0.0", true),
        ("2.18.4", false),
        ("1.17.4", false),
        ("", false),
        (nil, false),
    ] as [(String?, Bool)])
    func takesCustomFieldValuesSincePaperless219(version: String?, takes: Bool) {
        #expect(Paperless.takesCustomFieldValues(version: version) == takes)
    }

    @Test func sendsCustomFieldValuesAsAJSONObjectByID() {
        let body = String(decoding: Paperless.uploadBody(pdf: Data(), fileName: "a.pdf", title: "A", created: nil, storagePath: nil, customFields: [Paperless.TextField(id: 12, maximumLength: 128): "Lumen & Co", Paperless.TextField(id: 5, maximumLength: 128): "Personal/Home \"A\""], boundary: "XYZ"), as: UTF8.self)
        #expect(body.contains("--XYZ\r\nContent-Disposition: form-data; name=\"custom_fields\"\r\n\r\n{\"5\":\"Personal/Home \\\"A\\\"\",\"12\":\"Lumen & Co\"}\r\n--XYZ\r\nContent-Disposition: form-data; name=\"document\""))
    }

    @Test func cutsCustomFieldValuesToWhatPaperlessTakes() throws {
        let text = String(repeating: "e\u{301}", count: 100)
        let body = String(decoding: Paperless.uploadBody(pdf: Data(), fileName: "a.pdf", title: "A", created: nil, storagePath: nil, customFields: [Paperless.TextField(id: 5, maximumLength: 128): text, Paperless.TextField(id: 6, maximumLength: nil): text], boundary: "XYZ"), as: UTF8.self)
        #expect(body.unicodeScalars.contains("{\"5\":\"\(String(repeating: "e\u{301}", count: 64))\",\"6\":\"\(text)\"}\r\n".unicodeScalars))
    }

    @Test func sendsTheDocumentType() {
        let body = String(decoding: Paperless.uploadBody(pdf: Data(), fileName: "a.pdf", title: "A", created: nil, documentType: 9, storagePath: nil, boundary: "XYZ"), as: UTF8.self)
        #expect(body.contains("--XYZ\r\nContent-Disposition: form-data; name=\"document_type\"\r\n\r\n9\r\n"))
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
        #expect(!body.contains("custom_fields"))
        #expect(!body.contains("correspondent"))
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

    @Test func anUploadIsTakenOnlyWhenPaperlessAnswersTheIDOfItsTask() {
        let sent = URL(string: "https://paperless.example.com/api/documents/post_document/")!
        func outcome(_ status: Int, _ body: String, version: String? = nil) -> Paperless.Outcome {
            Paperless.uploadOutcome(status: status, body: Data(body.utf8), version: version, error: nil, sentTo: sent, answeredFrom: sent)
        }
        #expect(outcome(200, #""5f1c2a3e-0b9d-4c8e-9a61-2f7d3c4b5a6e""#) == .delivered)
        #expect(outcome(200, "<html><title>Sign in</title></html>") == .failed("The server did not answer like a Paperless-ngx server."))
        #expect(outcome(200, #"{"detail": "OK"}"#, version: "2.19.0") == .failed("The server did not answer like a Paperless-ngx server."))
        #expect(outcome(200, "", version: "2.19.0") == .delivered, "A background session can lose the body")
        #expect(outcome(200, "") == .failed("The server did not answer like a Paperless-ngx server."))
        #expect(outcome(503, "") == .retry("The server is not ready (error 503)."))
    }

    @Test func anUploadThatWasRedirectedFailed() {
        let sent = URL(string: "https://paperless.example.com/api/documents/post_document/")!
        let taskID = Data(#""5f1c2a3e-0b9d-4c8e-9a61-2f7d3c4b5a6e""#.utf8)
        func outcome(answeredFrom answered: String, status: Int = 200, error: URLError.Code? = nil) -> Paperless.Outcome {
            Paperless.uploadOutcome(status: status, body: taskID, version: "2.19.0", error: error, sentTo: sent, answeredFrom: URL(string: answered))
        }
        #expect(outcome(answeredFrom: "https://login.example.com/") == .failed("The server redirects to another address."))
        #expect(outcome(answeredFrom: "https://paperless.example.com/accounts/login/", status: 503) == .failed("The server redirects to another address."))
        #expect(outcome(answeredFrom: "http://paperless.example.com/api/documents/post_document/") == .failed("The server redirects to another address."))
        #expect(outcome(answeredFrom: "https://Paperless.Example.com:443/api/documents/post_document/") == .delivered)
        #expect(Paperless.uploadOutcome(status: nil, body: Data(), version: nil, error: .timedOut, sentTo: sent, answeredFrom: nil) == .retry("The server cannot be reached."))
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
        (.serverCertificateHasBadDate, .failed("The server's certificate is not trusted.")),
        (.secureConnectionFailed, .retry("The server cannot be reached.")),
    ])
    func tellsWhatANetworkErrorMeans(error: URLError.Code, outcome: Paperless.Outcome) {
        #expect(Paperless.outcome(status: nil, body: Data(), error: error) == outcome)
    }
}
