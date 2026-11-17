@testable import ScannerKit
import ScannerKitTesting
import Synchronization
import Testing

struct ProcessingGateTests {
    private final class Log: Sendable {
        private let events = Mutex<[String]>([])
        var all: [String] { events.withLock { $0 } }
        func append(_ event: String) { events.withLock { $0.append(event) } }
    }

    @Test func runsOneWorkAtATime() async {
        let gate = ProcessingGate()
        let log = Log()
        await withTaskGroup { group in
            for index in 0..<8 {
                group.addTask {
                    await gate.run {
                        log.append("start \(index)")
                        try? await Task.sleep(for: .milliseconds(5))
                        log.append("end \(index)")
                    }
                }
            }
        }
        let events = log.all
        #expect(events.count == 16)
        for pair in stride(from: 0, to: events.count, by: 2) {
            #expect(events[pair].replacing("start", with: "end") == events[pair + 1])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func startsNoWorkWhilePausedAndLetsTheWorkStartedFinish() async throws {
        let gate = ProcessingGate()
        let log = Log()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        let running = Task {
            await gate.run {
                didStart.finish()
                for await _ in released {}
                log.append("running")
            }
        }
        for await _ in started {}
        gate.isPaused = true
        let next = Task { await gate.run { log.append("next") } }
        while gate.waitingCount < 1 { try await Task.sleep(for: .milliseconds(1)) }
        release.finish()
        await running.value
        try await Task.sleep(for: .milliseconds(50))
        #expect(log.all == ["running"])

        gate.isPaused = false
        await next.value
        #expect(log.all == ["running", "next"])
        await gate.run { log.append("after") }
        #expect(log.all.last == "after")
    }

    @Test func keepsTheAppRunningUntilTheWorkIsDone() async {
        let background = RecordingBackground()
        let gate = ProcessingGate(background: background)
        await gate.run { #expect(background.running == 1) }
        await gate.finish { #expect(background.running == 1) }
        #expect(background.begun == 2)
        #expect(background.running == 0)
    }
}
