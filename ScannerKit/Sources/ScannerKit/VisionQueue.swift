import Foundation

/// Runs Vision's blocking requests off the Swift concurrency pool, which they need free to finish.
enum VisionQueue {
    private static let queue = DispatchQueue(label: "org.roneograph.vision", qos: .userInitiated, attributes: .concurrent)

    static func run<Result: Sendable>(_ work: @escaping @Sendable () -> Result) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
