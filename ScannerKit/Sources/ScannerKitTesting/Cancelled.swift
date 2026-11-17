/// Runs the operation in a task cancelled before it starts, as when the user leaves the screen it was for.
public func inCancelledTask<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await operation()
    }.value
}
