import Foundation

protocol WalkClock: Sendable {
    func now() -> Date
    func ticks(every interval: TimeInterval) -> AsyncStream<Date>
}

struct SystemWalkClock: WalkClock {
    func now() -> Date {
        Date()
    }

    func ticks(every interval: TimeInterval) -> AsyncStream<Date> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(interval))
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    continuation.yield(Date())
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
