import ScannerKit
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
}
