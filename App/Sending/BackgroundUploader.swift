import Foundation
import ScannerModels

/// Uploads in a background session: the system sends them even once the app is suspended or stopped, and waits for the network.
/// The app is never launched in the background for their results, as its scans cannot be read while the iPhone is locked; they come once it runs again.
@MainActor
final class BackgroundUploader: NSObject, Uploader {
    weak var archiver: Archiver?
    private var session: URLSession!
    /// The task of each scan, as started here or found in the session.
    private var tasks: [UUID: URLSessionTask] = [:]
    /// The tasks cancelled or replaced here, whose result nobody waits for; the system cancels the others, as when the app is force-quit.
    private var cancelled: Set<Int> = []
    private var responses: [Int: Data] = [:]

    init(identifier: String) {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = false
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        Task { _ = await uploadingScanIDs() }
    }

    func uploadingScanIDs() async -> Set<UUID> {
        for task in await session.allTasks where task.state != .completed {
            if let id = task.taskDescription.flatMap(UUID.init(uuidString:)), tasks[id] == nil { tasks[id] = task }
        }
        return Set(tasks.keys)
    }

    func upload(_ request: URLRequest, fromFile file: URL, scanID: UUID, after delay: Duration) {
        cancel(scanID: scanID)
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = scanID.uuidString
        if delay > .zero { task.earliestBeginDate = .now.addingTimeInterval(Double(delay.components.seconds)) }
        tasks[scanID] = task
        task.resume()
    }

    func cancel(scanID: UUID) {
        guard let task = tasks.removeValue(forKey: scanID) else { return }
        cancelled.insert(task.taskIdentifier)
        task.cancel()
    }

    /// A task of a previous launch that the session did not list was started again, so its result, if it comes after all, is dropped.
    private func complete(_ task: URLSessionTask, error: Error?) {
        let body = responses.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard cancelled.remove(task.taskIdentifier) == nil, let id = task.taskDescription.flatMap(UUID.init(uuidString:)), tasks[id].map({ $0 === task }) ?? true else { return }
        tasks[id] = nil
        let status = error == nil ? (task.response as? HTTPURLResponse)?.statusCode : nil
        archiver?.complete(UploadResult(scanID: id, status: status, body: body, error: error.map { ($0 as? URLError)?.code ?? .unknown }))
    }
}

extension BackgroundUploader: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated { responses[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated { complete(task, error: error) }
    }
}
